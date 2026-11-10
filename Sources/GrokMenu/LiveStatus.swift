import AppKit
import Foundation

/// Reads live bot state (running / typing / current activity) out of the running Grok Bot window.
///
/// Grok Bot keeps this state only in its renderer's memory, so the only way to get at it is the
/// Chromium DevTools protocol, which is available when Grok Bot was started with
/// `--remote-debugging-port`. Without that port this reports `.noDebugPort` and no live state.
final class LiveStatusClient {
    struct Snapshot: Equatable {
        var states: [String: LiveState] = [:]
        var openTitle: String?
        var openText: String?
    }

    private(set) var connection: LiveConnection = .appNotRunning
    private(set) var snapshot = Snapshot()
    var onChange: (() -> Void)?

    private let session = URLSession(configuration: .ephemeral)
    private var socket: URLSessionWebSocketTask?
    private var nextID = 1
    private var pollTask: Task<Void, Never>?

    func loadDemo() {
        connection = .connected
        snapshot = Snapshot(states: Demo.states)
    }

    func start() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    static var isGrokBotRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: GrokPaths.bundleID).isEmpty
    }

    /// Selects a bot in the Grok Bot window by clicking its sidebar row.
    func select(botNamed name: String) {
        guard connection == .connected else { return }
        let literal = (try? JSONSerialization.data(withJSONObject: [name])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let script = """
        (() => { const name = \(literal)[0];
          const row = [...document.querySelectorAll('aside button, [role=complementary] button')]
            .find(b => (b.getAttribute('aria-label') || '').split(',')[0] === name);
          if (row) row.click(); return !!row; })()
        """
        Task { _ = try? await self.evaluate(script) }
    }

    // MARK: - Polling

    private func tick() async {
        var newConnection = connection
        var newSnapshot = Snapshot()
        defer { publish(newConnection, newSnapshot) }

        guard Self.isGrokBotRunning else {
            disconnect()
            newConnection = .appNotRunning
            return
        }
        do {
            if socket == nil {
                guard let url = await findPageSocketURL() else {
                    newConnection = .noDebugPort
                    return
                }
                let task = session.webSocketTask(with: url)
                task.maximumMessageSize = 16 * 1024 * 1024
                task.resume()
                socket = task
            }
            let json = try await evaluate(Self.probeScript)
            newSnapshot = Self.parse(json)
            newConnection = .connected
        } catch {
            disconnect()
            newConnection = .failed(error.localizedDescription)
        }
    }

    private func publish(_ newConnection: LiveConnection, _ newSnapshot: Snapshot) {
        DispatchQueue.main.async {
            guard newConnection != self.connection || newSnapshot != self.snapshot else { return }
            self.connection = newConnection
            self.snapshot = newSnapshot
            self.onChange?()
        }
    }

    private func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - DevTools protocol

    private func candidatePorts() -> [Int] {
        var ports = [GrokPaths.debugPort]
        if let text = try? String(contentsOf: GrokPaths.devToolsActivePort, encoding: .utf8),
           let port = Int(text.split(separator: "\n").first ?? ""), !ports.contains(port) {
            ports.append(port)
        }
        return ports
    }

    private func findPageSocketURL() async -> URL? {
        for port in candidatePorts() {
            guard let listURL = URL(string: "http://127.0.0.1:\(port)/json/list") else { continue }
            var request = URLRequest(url: listURL)
            request.timeoutInterval = 1
            guard let (data, _) = try? await session.data(for: request),
                  let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            let pages = targets.filter { $0["type"] as? String == "page" }
            let match = pages.first { ($0["title"] as? String ?? "").contains("Grok Bot") }
                ?? pages.first { ($0["url"] as? String ?? "").contains("app.asar") }
            if let text = match?["webSocketDebuggerUrl"] as? String, let url = URL(string: text) {
                return url
            }
        }
        return nil
    }

    private func evaluate(_ expression: String) async throws -> String {
        guard let socket else { throw URLError(.notConnectedToInternet) }
        let id = nextID
        nextID += 1
        let payload: [String: Any] = [
            "id": id, "method": "Runtime.evaluate",
            "params": ["expression": expression, "returnByValue": true],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await socket.send(.string(String(data: data, encoding: .utf8)!))

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let message = try await socket.receive()
            guard case .string(let text) = message,
                  let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  object["id"] as? Int == id else { continue }
            let result = (object["result"] as? [String: Any])?["result"] as? [String: Any]
            if let value = result?["value"] as? String { return value }
            if let value = result?["value"] as? Bool { return value ? "true" : "false" }
            throw URLError(.cannotParseResponse)
        }
        throw URLError(.timedOut)
    }

    // MARK: - Parsing

    private static func parse(_ json: String) -> Snapshot {
        var snapshot = Snapshot()
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return snapshot
        }
        for (id, value) in object["agents"] as? [String: [String: Any]] ?? [:] {
            var state = LiveState()
            state.isRunning = value["isRunning"] as? Bool ?? false
            state.isComposing = value["isComposing"] as? Bool ?? false
            state.isAwaitingUser = value["isAwaiting"] as? Bool ?? false
            state.awaitingReason = value["awaitingReason"] as? String
            if let activity = value["activity"] as? [String: Any] {
                state.activity = Activity(
                    kind: activity["kind"] as? String, tool: activity["tool"] as? String,
                    detail: activity["detail"] as? String, target: activity["target"] as? String)
            }
            snapshot.states[id] = state
        }
        if let open = object["open"] as? [String: Any] {
            snapshot.openTitle = open["title"] as? String
            snapshot.openText = (open["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return snapshot
    }

    /// Runs inside the Grok Bot window. Walks the React tree for roster rows (objects carrying
    /// `isRunning` / `currentActivity`) and reads the status line of the open conversation.
    private static let probeScript = #"""
    (() => {
      const agents = {};
      const isAgent = o => o && typeof o === 'object' && typeof o.id === 'string'
        && typeof o.name === 'string' && 'avatarShape' in o && 'isRunning' in o;
      const rank = o => (o.currentActivity ? 2 : 0) + (o.isRunning || o.isComposingMessage ? 1 : 0);
      // The tree holds both the stored roster row (never running) and the row merged with live
      // state; the one showing activity is the live one.
      const take = o => {
        const seen = agents[o.id];
        const score = rank(o);
        if (seen && seen.rank >= score) return;
        const a = o.currentActivity, w = o.awaitingUserResponse;
        agents[o.id] = {
          rank: score,
          isRunning: !!(o.isRunning || o.isRunningTurn),
          isComposing: !!o.isComposingMessage,
          isAwaiting: w != null,
          awaitingReason: w ? (w.reasonCopy || null) : null,
          activity: a ? { kind: a.kind ?? null, tool: a.tool ?? null, detail: a.detail ?? null,
                          target: typeof a.target === 'string' ? a.target : null } : null,
        };
      };
      const scan = (v, depth) => {
        if (!v || typeof v !== 'object') return;
        if (isAgent(v)) return take(v);
        if (Array.isArray(v)) { if (v.length && v.length < 1000 && isAgent(v[0])) v.forEach(x => isAgent(x) && take(x)); return; }
        if (depth <= 0 || v.$$typeof || v.nodeType || v instanceof Map || v instanceof Set) return;
        let n = 0;
        for (const k in v) { if (++n > 40) break; let c; try { c = v[k]; } catch { continue; } scan(c, depth - 1); }
      };
      const root = document.getElementById('root');
      const key = root && Object.keys(root).find(k => k.startsWith('__reactContainer$'));
      let fiber = key ? root[key] : null;
      if (fiber && fiber.stateNode && fiber.stateNode.current) fiber = fiber.stateNode.current;
      const stack = fiber ? [fiber] : [];
      let visited = 0;
      while (stack.length && visited < 200000) {
        const f = stack.pop(); visited++;
        scan(f.memoizedProps, 1);
        if (f.sibling) stack.push(f.sibling);
        if (f.child) stack.push(f.child);
      }
      const mark = document.querySelector('.sand-activity-mark');
      const label = mark && mark.querySelector('.sand-activity-label__text, .sand-activity-mark__label');
      const heading = document.getElementById('sand-conversation-heading');
      return JSON.stringify({
        agents,
        open: { title: heading ? heading.innerText.trim() : null,
                text: label ? label.innerText.replace(/\s+/g, ' ').trim() : null },
      });
    })()
    """#
}
