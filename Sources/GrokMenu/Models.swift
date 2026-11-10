import Foundation

/// One bot from Grok Bot's persisted roster.
struct Bot: Equatable {
    var id: String
    var name: String
    var shape: String
    var color: String
    var photoKey: String?
    var lastActivityAt: Double
    var preview: String
    var isHidden: Bool
    var unreadCount: Int
}

/// Live, in-memory state of one bot, read from the running Grok Bot window.
struct LiveState: Equatable {
    var isRunning = false
    var isComposing = false
    var isAwaitingUser = false
    var awaitingReason: String?
    var activity: Activity?

    var isActive: Bool { isAwaitingUser || isRunning || isComposing }
}

struct Activity: Equatable {
    var kind: String?
    var tool: String?
    var detail: String?
    var target: String?
}

enum LiveConnection: Equatable {
    case appNotRunning
    case noDebugPort
    case connected
    case failed(String)
}

enum GrokPaths {
    static let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Grok Bot")
    static let persistence = appSupport.appendingPathComponent("sand-client-persistence")
    static let avatars = appSupport.appendingPathComponent("roster-avatars")
    static let devToolsActivePort = appSupport.appendingPathComponent("DevToolsActivePort")
    static let bundleID = "com.anysphere.sand"
    static let debugPort = 9347
}

extension String {
    func truncated(_ max: Int) -> String {
        count <= max ? self : String(prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Text shown for a bot's current task. Mirrors Grok Bot's own activity labels.
func activityText(for live: LiveState) -> String {
    if live.isAwaitingUser { return live.awaitingReason?.truncated(60) ?? "Waiting for you" }
    if live.isComposing { return "Typing" }
    guard let activity = live.activity else { return "Working" }
    if activity.kind == "thinking" { return "Thinking" }
    guard let tool = activity.tool, !tool.isEmpty else { return "Working" }
    let detail = activity.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasDetail = !(detail ?? "").isEmpty

    switch tool {
    case "SetStatus":
        guard hasDetail, var text = detail else { return "Working" }
        if text.lowercased().hasPrefix("is ") { text = String(text.dropFirst(3)) }
        return (text.prefix(1).uppercased() + text.dropFirst()).truncated(60)
    case "WebSearch", "PlacesSearch", "WeatherForecast", "RestaurantSearch", "FlightSearch",
         "FlightDetails", "ArrangeFlights":
        return "Searching the web"
    case "WebFetch": return "Reading the web"
    case "Read", "BoxRead", "Skill": return "Reading a file"
    case "MachineShell": return hasDetail ? "Drafting the file" : "On your computer"
    case "Shell", "BoxShell": return hasDetail ? "Drafting the file" : "Running commands"
    case "CopyToBox", "CopyFromBox", "CopyBotFile": return "Organizing files"
    case "Await", "AwaitShell": return "Waiting on a command"
    case "GenerateImage": return "Generating a photo"
    case "GenerateVideo": return "Generating a video"
    case "CloudAgent": return "Coding"
    case "Task": return activity.target == "computerUse" ? "On its computer" : "Working"
    case "Screenshot", "Computer", "request_box_help": return "On its computer"
    case "request_user_form", "RequestUserForm": return "Waiting for you"
    case "remap_user_form_targets", "RemapUserFormTargets": return "Browsing the web"
    case "SendToAgent", "UpdateAgent": return "Messaging another assistant"
    case "CreateAgent", "ReactToMessage", "SendIMessage": return "Messaging"
    case "CheckSubscriptionUsage": return "Checking usage"
    case "FetchConnectedActivity": return detail == "cursor" ? "Working" : "On your computer"
    case "CallMcpTool":
        return hasDetail ? "Connecting to \(detail!)".truncated(60) : "Connecting to a third party app"
    default:
        return tool.hasPrefix("browser_") ? "Browsing the web" : "Working"
    }
}
