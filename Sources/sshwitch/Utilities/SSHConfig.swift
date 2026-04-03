import Foundation

enum SSHConfig {
    private static let configPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config").path
    }()

    private static let backupPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config.bak").path
    }()

    /// Appends a Host block to ~/.ssh/config. Creates the file if absent.
    /// Always backs up before the first modification.
    static func appendBlock(_ block: String, dryRun: Bool = false) throws {
        let existing = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""

        if dryRun {
            Output.print("[dry-run] Would append to ~/.ssh/config:")
            Output.print(block)
            return
        }

        // Backup
        if FileManager.default.fileExists(atPath: configPath),
           !FileManager.default.fileExists(atPath: backupPath) {
            try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
            Output.info("Backed up ~/.ssh/config to ~/.ssh/config.bak")
        }

        let newContent = existing.isEmpty ? block : existing + "\n" + block
        try atomicWrite(content: newContent, to: configPath)
    }

    // MARK: - Atomic write

    private static func atomicWrite(content: String, to path: String) throws {
        let tempPath = path + ".tmp.\(ProcessInfo.processInfo.processIdentifier)"
        guard let data = content.data(using: .utf8) else {
            throw RuntimeError("Failed to encode SSH config content.")
        }
        try data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
        try FileManager.default.moveItem(atPath: tempPath, toPath: path)
        // Set config file permissions to 600
        chmod(path, 0o600)
    }
}
