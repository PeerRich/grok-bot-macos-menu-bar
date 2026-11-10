import Foundation

/// Reads the bot list Grok Bot persists on disk.
///
/// Grok Bot stores each client "slice" as `<base32(key)>.blob` holding
/// `{"schemaVersion":n,"value":…}`. The roster slice key ends in `.roster.last-roster`.
final class RosterStore {
    private(set) var bots: [Bot] = []
    private(set) var selectedBotID: String?
    private var rosterStamp: Date?

    /// Returns true when the bot list changed.
    @discardableResult
    func reload() -> Bool {
        let before = bots
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: GrokPaths.persistence, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return false }

        var roster: (url: URL, date: Date)?
        var selection: URL?
        for url in files where url.pathExtension == "blob" {
            guard let key = Base32.decodeString(url.deletingPathExtension().lastPathComponent) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if key.hasSuffix(".roster.last-roster"), roster == nil || date > roster!.date {
                roster = (url, date)
            } else if key.hasSuffix(".selection.last-agent") {
                selection = url
            }
        }

        if let selection, let value = Self.sliceValue(selection) as? [String: Any] {
            selectedBotID = value["agentId"] as? String
        }
        guard let roster, roster.date != rosterStamp else { return false }
        guard let value = Self.sliceValue(roster.url) as? [String: Any],
              let rows = value["rows"] as? [[String: Any]] else { return false }
        rosterStamp = roster.date
        bots = rows.compactMap(Self.bot(from:))
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        return bots != before
    }

    private static func sliceValue(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["value"]
    }

    private static func bot(from row: [String: Any]) -> Bot? {
        guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
        let entry = row["lastEntry"] as? [String: Any]
        let previewText = (entry?["sessionPreview"] as? [String: Any])?["text"] as? String
            ?? entry?["text"] as? String ?? ""
        return Bot(
            id: id,
            name: name.isEmpty ? "New Bot" : name,
            shape: row["avatarShape"] as? String ?? "",
            color: row["avatarColor"] as? String ?? "",
            photoKey: (row["avatarPhoto"] as? [String: Any])?["key"] as? String,
            lastActivityAt: (row["lastActivityAt"] as? Double) ?? (row["updatedAt"] as? Double) ?? 0,
            preview: plainText(previewText),
            isHidden: row["isHiddenFromSidebar"] as? Bool == true || row["isRemovedFromSidebar"] as? Bool == true,
            unreadCount: row["unreadCount"] as? Int ?? 0)
    }

    /// Collapses whitespace and turns markdown links `[label](url)` into `label`.
    private static func plainText(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }
        for token in ["**", "`"] { result = result.replacingOccurrences(of: token, with: "") }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum Base32 {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567".utf8)

    static func decodeString(_ text: String) -> String? {
        var bits: UInt32 = 0
        var bitCount = 0
        var bytes: [UInt8] = []
        for character in text.lowercased().utf8 {
            if character == UInt8(ascii: "=") { break }
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            bits = (bits << 5) | UInt32(value)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((bits >> UInt32(bitCount)) & 0xFF))
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
