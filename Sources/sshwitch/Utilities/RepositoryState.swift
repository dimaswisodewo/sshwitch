import Foundation

enum RepositoryState {
    static func resolvedPath(_ explicit: String?) throws -> String {
        guard let explicit else { return FileManager.default.currentDirectoryPath }
        let expanded = (explicit as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeError("Path '\(explicit)' does not exist or is not a directory.")
        }
        return expanded
    }

    static func isGitRepository(at path: String) -> Bool {
        guard let result = try? Shell.run("/usr/bin/git", arguments: ["-C", path, "rev-parse", "--git-dir"]) else {
            return false
        }
        return result.succeeded
    }

    static func requireGitRepository(at path: String) throws {
        guard isGitRepository(at: path) else { throw RuntimeError("'\(path)' is not a git repository.") }
    }

    static func localSSHCommand(at path: String) -> String? {
        guard isGitRepository(at: path),
              let result = try? Shell.run("/usr/bin/git", arguments: ["-C", path, "config", "--local", "core.sshCommand"]),
              result.succeeded, !result.output.isEmpty else { return nil }
        return result.output
    }

    static func keyPath(from sshCommand: String) -> String? {
        let parts = sshCommand.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let index = parts.firstIndex(of: "-i"), parts.indices.contains(index + 1) else { return nil }
        return parts[index + 1]
    }

    static func remoteHost(at path: String) -> String? {
        guard let result = try? Shell.run("/usr/bin/git", arguments: ["-C", path, "remote", "get-url", "origin"]),
              result.succeeded else { return nil }
        let url = result.output
        if url.hasPrefix("git@"), let colon = url.firstIndex(of: ":") {
            return String(url[url.index(url.startIndex, offsetBy: 4)..<colon])
        }
        if let parsed = URL(string: url), parsed.scheme == "ssh" { return parsed.host }
        return nil
    }
}
