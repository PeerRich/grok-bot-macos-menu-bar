import AppKit

/// `GrokMenu --demo` shows made-up bots instead of reading Grok Bot, for screenshots.
/// `GrokMenu --demo --screenshot out.png` opens the menu, captures it and exits.
enum Demo {
    static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    private static let rows: [(name: String, shape: String, color: String, preview: String, live: LiveState?)] = [
        ("Sales", "star", "violet", "", LiveState(isRunning: true, activity: Activity(tool: "SetStatus", detail: "is running the full task"))),
        ("Research", "cloud", "blue", "", LiveState(isRunning: true, activity: Activity(tool: "WebSearch"))),
        ("Inbox", "tablet", "green", "", LiveState(isRunning: true, isComposing: true)),
        ("Release Notes", "hex", "orange", "Draft for 4.2 is ready with three highlights.", nil),
        ("Travel", "teardrop", "cyan", "Booked the 9:40 train to Hamburg.", nil),
        ("Support", "squircle", "magenta", "Answered 12 tickets overnight, flagged two.", nil),
        ("Finance", "pebble", "yellow", "October invoices are reconciled.", nil),
        ("Standup", "wedge", "red", "Posted today's summary in the team channel.", nil),
        ("Recipes", "heart", "brown", "Shopping list for the week is in your notes.", nil),
    ]

    static var bots: [Bot] {
        rows.enumerated().map { index, row in
            Bot(id: "demo-\(index)", name: row.name, shape: row.shape, color: row.color, photoKey: nil,
                lastActivityAt: Double(rows.count - index), preview: row.preview, isHidden: false, unreadCount: 0)
        }
    }

    static var states: [String: LiveState] {
        Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { index, row in
            row.live.map { ("demo-\(index)", $0) }
        })
    }

    static var screenshotPath: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// Opens the status item's menu, captures the menu window, and writes it under a drawn menu
    /// bar on a plain backdrop (so nothing else on screen ends up in the picture). The status
    /// item is drawn from its own image and title because its window belongs to the system.
    static func captureMenu(of statusItem: NSStatusItem, to path: String) {
        let timer = Timer(timeInterval: 1.2, repeats: false) { _ in
            let pid = ProcessInfo.processInfo.processIdentifier
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
                .filter { $0[kCGWindowOwnerPID as String] as? Int32 == pid }
            func capture(layer: Int, shadow: Bool) -> NSImage? {
                guard let window = windows.first(where: { $0[kCGWindowLayer as String] as? Int == layer }),
                      let id = window[kCGWindowNumber as String] as? Int else { return nil }
                let file = NSTemporaryDirectory() + "grokmenu-\(layer).png"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-l", "\(id)"] + (shadow ? [] : ["-o"]) + [file]
                try? process.run()
                process.waitUntilExit()
                defer { try? FileManager.default.removeItem(atPath: file) }
                return NSImage(contentsOfFile: file).flatMap { NSBitmapImageRep(data: $0.tiffRepresentation ?? Data()) }
                    .map { rep in
                        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
                        image.addRepresentation(rep)
                        rep.size = image.size
                        return image
                    }
            }
            let menuImage = capture(layer: Int(CGWindowLevelForKey(.popUpMenuWindow)), shadow: true)
            statusItem.menu?.cancelTracking()
            guard let menuImage else {
                FileHandle.standardError.write(Data("capture failed (screen recording permission?)\n".utf8))
                exit(1)
            }
            compose(menu: menuImage, icon: statusItem.button?.image, title: statusItem.button?.title ?? "", to: path)
            exit(0)
        }
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { statusItem.button?.performClick(nil) }
    }

    /// Sizes are in pixels of the captured (Retina) menu image.
    private static func compose(menu: NSImage, icon: NSImage?, title: String, to path: String) {
        let margin: CGFloat = 60, bar: CGFloat = 56
        let size = NSSize(width: menu.size.width + margin * 2, height: bar + menu.size.height + margin - 30)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: [NSColor(hex: "#2B2350"), NSColor(hex: "#3F2F7A"), NSColor(hex: "#1B3A6B")])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -50)
        NSColor(white: 0, alpha: 0.35).setFill()
        NSRect(x: 0, y: size.height - bar, width: size.width, height: bar).fill()

        // The captured menu carries its shadow as padding around the visible panel.
        let shadowPad = menu.size.width * 0.1
        menu.draw(in: NSRect(x: margin, y: size.height - bar - menu.size.height + shadowPad * 0.55,
                             width: menu.size.width, height: menu.size.height))
        let iconSide: CGFloat = 34
        let itemX = margin + shadowPad + 16
        icon?.draw(in: NSRect(x: itemX, y: size.height - bar + (bar - iconSide) / 2, width: iconSide, height: iconSide))
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 26, weight: .medium), .foregroundColor: NSColor.white,
        ])
        text.draw(at: NSPoint(x: itemX + iconSide + 2, y: size.height - bar + (bar - text.size().height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
