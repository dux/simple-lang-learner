import Foundation

enum ChatError: LocalizedError {
    case notInstalled(String)
    case process(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name): return "\(name) not found"
        case .process(let msg): return msg.isEmpty ? "backend failed" : String(msg.suffix(300))
        case .empty: return "no reply"
        }
    }
}

// Master class. One subclass per CLI agent below; each overrides id, displayName,
// isAvailable() and complete(). Shared process/PATH helpers live here. Trimmed
// from swift-learn-lang's ChatBackend to just the stateless one-shot path we need
// for word generation.
class ChatBackend: @unchecked Sendable {
    var id: String { "" }
    var displayName: String { "" }
    func isAvailable() -> Bool { false }

    // Stateless one-shot completion. Prompt in, raw model text out.
    func complete(_ prompt: String) async throws -> String {
        throw ChatError.process("not implemented")
    }

    // The app's GUI launch PATH is minimal, so resolve CLIs from the known install
    // locations directly. This also bypasses the codex zsh wrapper.
    static func resolve(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/\(name)"),
            home.appendingPathComponent(".bun/bin/\(name)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // Run a subprocess off the main actor; read pipes before waitUntilExit so a
    // full buffer can't deadlock. Prompts go in as arguments, never via stdin.
    nonisolated static func run(_ executable: URL, _ args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = executable
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw ChatError.process(String(data: errData, encoding: .utf8) ?? "")
            }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    static func jsonLines(_ text: String) -> [[String: Any]] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { return nil }
            return obj
        }
    }
}

// claude -p "<prompt>"  ->  the reply text on stdout, nothing else. (We avoid
// --output-format json: this CLI version emits a JSON array of stream events, not
// a single {result} object, and we only need a stateless one-shot. stdin is the
// null device in run(), so -p does not stall waiting for piped input.)
final class ClaudeBackend: ChatBackend, @unchecked Sendable {
    override var id: String { "claude" }
    override var displayName: String { "claude" }
    override func isAvailable() -> Bool { Self.resolve("claude") != nil }

    override func complete(_ prompt: String) async throws -> String {
        guard let bin = Self.resolve("claude") else { throw ChatError.notInstalled("claude") }
        let out = try await Self.run(bin, ["-p", prompt])
        let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChatError.empty }
        return text
    }
}

// opencode run "<prompt>" --format json  ->  JSONL; text in part.text on type:"text".
final class OpencodeBackend: ChatBackend, @unchecked Sendable {
    override var id: String { "opencode" }
    override var displayName: String { "opencode" }
    override func isAvailable() -> Bool { Self.resolve("opencode") != nil }

    override func complete(_ prompt: String) async throws -> String {
        guard let bin = Self.resolve("opencode") else { throw ChatError.notInstalled("opencode") }
        let events = Self.jsonLines(try await Self.run(bin, ["run", prompt, "--format", "json"]))
        var parts: [(id: String, text: String)] = []
        for e in events where e["type"] as? String == "text" {
            guard let part = e["part"] as? [String: Any],
                  part["type"] as? String == "text",
                  let t = part["text"] as? String else { continue }
            let pid = part["id"] as? String ?? ""
            if let i = parts.firstIndex(where: { $0.id == pid }) { parts[i].text = t }
            else { parts.append((pid, t)) }
        }
        let text = parts.map(\.text).joined()
        guard !text.isEmpty else { throw ChatError.empty }
        return text
    }
}

// codex exec --json --skip-git-repo-check "<prompt>"  ->  JSONL agent_message items.
final class CodexBackend: ChatBackend, @unchecked Sendable {
    override var id: String { "codex" }
    override var displayName: String { "codex" }
    override func isAvailable() -> Bool { Self.resolve("codex") != nil }

    override func complete(_ prompt: String) async throws -> String {
        guard let bin = Self.resolve("codex") else { throw ChatError.notInstalled("codex") }
        let events = Self.jsonLines(try await Self.run(
            bin, ["exec", "--json", "--skip-git-repo-check", prompt]))
        let text = events.compactMap { e -> String? in
            guard e["type"] as? String == "item.completed",
                  let item = e["item"] as? [String: Any],
                  item["type"] as? String == "agent_message" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")
        guard !text.isEmpty else { throw ChatError.empty }
        return text
    }
}

enum ChatBackends {
    static let all: [ChatBackend] = [ClaudeBackend(), CodexBackend(), OpencodeBackend()]
    static func byID(_ id: String) -> ChatBackend { all.first { $0.id == id } ?? all[0] }
}
