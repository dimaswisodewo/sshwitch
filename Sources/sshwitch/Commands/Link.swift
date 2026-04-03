import ArgumentParser
import Foundation

struct Link: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Link an SSH key to a Git repository via core.sshCommand.",
        discussion: """
        Examples:
          sshwitch link --key work
          sshwitch link --key personal --path ~/code/myrepo
          sshwitch link --key work --dry-run

        Sets git's core.sshCommand for the repository so pushes and pulls use
        the specified key. If --path is omitted, the current directory is used.
        This does not modify ~/.ssh/config or any remote URL.
        """
    )

    @Option(name: .long, help: "Key name (e.g., work) or absolute path to private key.")
    var key: String

    @Option(name: .long, help: "Path to the git repository (defaults to current directory).")
    var path: String?

    @Flag(name: .long, help: "Print intended actions without executing them.")
    var dryRun: Bool = false

    func run() throws {
        let repoPath = try resolvedRepoPath()
        let keyPath = try KeyResolver.resolve(key)
        let sshCommand = "ssh -i \(keyPath) -o IdentitiesOnly=yes"

        if dryRun {
            Output.print("[dry-run] Would run in \(repoPath):")
            Output.print("[dry-run]   git config core.sshCommand \"\(sshCommand)\"")
            return
        }

        // Step 1: Validate repo
        Output.step(1, of: 2, "Validating git repository at '\(repoPath)'...")
        try validateGitRepo(at: repoPath)

        // Step 2: Set git config
        Output.step(2, of: 2, "Linking key '\(keyPath)' to repo...")
        let result = try Shell.run("/usr/bin/git", arguments: [
            "-C", repoPath,
            "config", "core.sshCommand", sshCommand
        ])

        guard result.succeeded else {
            throw RuntimeError("git config failed (exit \(result.exitCode)).")
        }

        Output.print("")
        Output.success("Key linked. Git operations in this repo will now use '\(keyPath)'.")
        Output.print("")
        Output.hint("Verify the link:   git -C \(repoPath) config core.sshCommand")
        Output.hint("Test connectivity:  sshwitch doctor")
    }

    // MARK: - Helpers

    private func resolvedRepoPath() throws -> String {
        if let explicit = path {
            let expanded = (explicit as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
                throw RuntimeError("Path '\(explicit)' does not exist or is not a directory.")
            }
            return expanded
        }
        return FileManager.default.currentDirectoryPath
    }

    private func validateGitRepo(at repoPath: String) throws {
        let result = try Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "rev-parse", "--git-dir"])
        guard result.succeeded else {
            throw RuntimeError("'\(repoPath)' is not a git repository.")
        }
    }
}
