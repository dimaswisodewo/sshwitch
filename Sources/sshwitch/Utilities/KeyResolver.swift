import Foundation

enum KeyResolver {
    /// Resolves a key name or absolute path to a verified absolute path under ~/.ssh/.
    /// Throws if the resolved private key file does not exist.
    static func resolve(_ nameOrPath: String) throws -> String {
        let path: String
        if nameOrPath.hasPrefix("/") || nameOrPath.hasPrefix("~") {
            // Treat as explicit path
            path = (nameOrPath as NSString).expandingTildeInPath
        } else {
            // Treat as a bare name → ~/.ssh/<name>
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            path = "\(home)/.ssh/\(nameOrPath)"
        }

        guard FileManager.default.fileExists(atPath: path) else {
            throw RuntimeError("SSH key not found at '\(path)'. Generate one with: sshwitch gen --name \(nameOrPath) --email <email>")
        }
        return path
    }
}
