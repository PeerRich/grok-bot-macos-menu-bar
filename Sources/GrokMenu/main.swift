import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let roster = RosterStore()
    private let live = LiveStatusClient()
    private var rosterTimer: Timer?
    private var primaryBotID: String?
    private var menuSignature = ""
    private var isMenuOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading

        if Demo.isEnabled {
            roster.loadDemo()
            live.loadDemo()
            refresh()
            if let path = Demo.screenshotPath { Demo.captureMenu(of: statusItem, to: path) }
            return
        }

        roster.reload()
        live.onChange = { [weak self] in self?.refresh() }
        live.start()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            if self?.roster.reload() == true { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rosterTimer = timer
        refresh()

        if CommandLine.arguments.contains("--dump") { dumpAndExit() }
    }

    // MARK: - State

    private struct Row {
        var bot: Bot
        var live: LiveState?
        var text: String
    }

    private func liveState(for bot: Bot) -> LiveState? { live.snapshot.states[bot.id] }

    private func activeRows() -> [Row] {
        roster.bots.compactMap { bot -> Row? in
            guard let state = liveState(for: bot), state.isActive else { return nil }
            var text = activityText(for: state)
            // The open conversation shows the exact phrase Grok Bot renders; prefer it.
            if !state.isAwaitingUser, let shown = live.snapshot.openText,
               live.snapshot.openTitle == bot.name {
                text = shown.truncated(60)
            }
            return Row(bot: bot, live: state, text: text)
        }
    }

    private func refresh() {
        let active = activeRows()
        updateStatusItem(active)
        let signature = buildSignature(active)
        if signature != menuSignature {
            menuSignature = signature
            rebuildMenu(active)
        }
    }

    private func buildSignature(_ active: [Row]) -> String {
        let activePart = active.map { "\($0.bot.id)=\($0.text)" }.joined(separator: ";")
        let botsPart = roster.bots.map { "\($0.id)|\($0.name)|\($0.preview)|\($0.isHidden)|\($0.unreadCount)|\($0.shape)|\($0.color)" }
            .joined(separator: ";")
        return "\(live.connection)#\(activePart)#\(botsPart)"
    }

    // MARK: - Menu bar item

    private func updateStatusItem(_ active: [Row]) {
        guard let button = statusItem.button else { return }
        // Keep showing the same bot while it stays active so the title does not jump around.
        let primary = active.first { $0.bot.id == primaryBotID }
            ?? active.first { $0.live?.isAwaitingUser == false }
            ?? active.first
        primaryBotID = primary?.bot.id

        guard let primary else {
            button.image = Avatar.templateIcon(size: 17)
            button.title = ""
            button.toolTip = "Grok Bot: no active bots"
            return
        }
        button.image = Avatar.image(for: primary.bot, size: 17)
        let more = active.count > 1 ? "  +\(active.count - 1)" : ""
        button.title = " " + primary.text.truncated(38) + more
        button.toolTip = active.map { "\($0.bot.name): \($0.text)" }.joined(separator: "\n")
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    private func rebuildMenu(_ active: [Row]) {
        menu.removeAllItems()
        let activeIDs = Set(active.map(\.bot.id))

        menu.addItem(.sectionHeader(title: "Active"))
        if active.isEmpty {
            menu.addItem(disabledItem(live.connection == .connected ? "No active bots" : "Live status unavailable"))
        }
        for row in active { menu.addItem(botItem(row.bot, subtitle: row.text)) }

        menu.addItem(.separator())

        let rest = roster.bots.filter { !activeIDs.contains($0.id) }
        for bot in rest where !bot.isHidden { menu.addItem(botItem(bot, subtitle: bot.preview.truncated(50))) }

        let hidden = rest.filter(\.isHidden)
        if !hidden.isEmpty {
            let parent = NSMenuItem(title: "Hidden Bots (\(hidden.count))", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for bot in hidden { submenu.addItem(botItem(bot, subtitle: bot.preview.truncated(50))) }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        if roster.bots.isEmpty { menu.addItem(disabledItem("No bots found. Open Grok Bot and sign in.")) }

        menu.addItem(.separator())
        addConnectionItems()
        menu.addItem(actionItem("Open Grok Bot", #selector(openGrokBot)))
        menu.addItem(actionItem("Quit Grok Menu", #selector(quit), key: "q"))
    }

    private func addConnectionItems() {
        switch live.connection {
        case .connected:
            break
        case .appNotRunning:
            menu.addItem(disabledItem("Grok Bot is not running"))
            menu.addItem(actionItem("Start Grok Bot with Live Status", #selector(launchWithLiveStatus)))
        case .noDebugPort, .failed:
            menu.addItem(disabledItem("Live status is off for this Grok Bot session"))
            menu.addItem(actionItem("Enable Live Status (Relaunch Grok Bot)…", #selector(enableLiveStatus)))
        }
    }

    private func botItem(_ bot: Bot, subtitle: String) -> NSMenuItem {
        let title = bot.unreadCount > 0 ? "\(bot.name.truncated(40))  •" : bot.name.truncated(40)
        let item = NSMenuItem(title: title, action: #selector(openBot(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = bot.id
        item.image = Avatar.image(for: bot, size: 26)
        if !subtitle.isEmpty { item.subtitle = subtitle }
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    private var grokBotURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: GrokPaths.bundleID) }

    @objc private func openBot(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let bot = roster.bots.first(where: { $0.id == id }) {
            live.select(botNamed: bot.name)
        }
        openGrokBot()
    }

    @objc private func openGrokBot() {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: GrokPaths.bundleID).first {
            running.activate()
        } else if let url = grokBotURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func launchWithLiveStatus() {
        guard let url = grokBotURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--remote-debugging-port=\(GrokPaths.debugPort)"]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @objc private func enableLiveStatus() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Relaunch Grok Bot to enable live status?"
        alert.informativeText = """
        Grok Bot only keeps "what each bot is doing right now" in memory. To read it, Grok Menu \
        restarts Grok Bot with a local debugging port (127.0.0.1:\(GrokPaths.debugPort)).

        While that port is open, other programs on this Mac could also inspect and control the \
        Grok Bot window. Anything Grok Bot is doing on this Mac right now may be interrupted by \
        the restart.
        """
        alert.addButton(withTitle: "Relaunch Grok Bot")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: GrokPaths.bundleID)
        running.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0..<40 where LiveStatusClient.isGrokBotRunning {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !LiveStatusClient.isGrokBotRunning else { return }
            self.launchWithLiveStatus()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Debug

    /// `GrokMenu --dump` prints what the menu would show, then exits.
    private func dumpAndExit() {
        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard self.live.connection == .connected || Date().timeIntervalSince(started) > 4 else { return }
            print("connection: \(self.live.connection)")
            print("menu bar: \(self.statusItem.button?.title ?? "")")
            for item in self.menu.items {
                if item.isSeparatorItem { print("  ────────"); continue }
                print("  \(item.title)" + (item.subtitle.map { "  —  \($0)" } ?? ""))
            }
            exit(0)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
