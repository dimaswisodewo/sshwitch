import ArgumentParser
import Foundation

struct Unlink: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Unlink an SSH key from a Git repository.",
        discussion: """
        Examples:
          sshwitch unlink
          sshwitch unlink --path ~/code/myrepo
          sshwitch unlink --dry-run

        Removes git's core.sshCommand for the repository, reverting to the
        default SSH key resolution. If --path is omitted, the current directory
        is used.
        """
    )

    @Option(name: .long, help: "Path to the git repository (defaults to current directory).")
    var path: String?

    @Flag(name: .long, help: "Print intended actions without executing them.")
    var dryRun: Bool = false

    func run() throws {
        let repoPath = try resolvedRepoPath()

        // Step 1: Validate repo
        Output.step(1, of: 2, "Validating git repository at '\(repoPath)'...")
        try validateGitRepo(at: repoPath)

        // Step 2: Read current link
        let current = try Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "config", "core.sshCommand"])
        guard current.succeeded, !current.output.isEmpty else {
            Output.warn("No SSH key is linked to '\(repoPath)'.")
            return
        }

        Output.print("")
        Output.print("Currently linked: \(Output.colored(current.output, .bold))")
        Output.print("")

        if dryRun {
            Output.print("[dry-run] Would run in \(repoPath):")
            Output.print("[dry-run]   git config --unset core.sshCommand")
            return
        }

        // Step 3: Unset
        Output.step(2, of: 2, "Unlinking SSH key from repo...")
        let result = try Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "config", "--unset", "core.sshCommand"])
        guard result.succeeded else {
            throw RuntimeError("git config --unset failed (exit \(result.exitCode)).")
        }

        Output.print("")
        Output.success("SSH key unlinked. Git operations in this repo will now use the default key.")
        Output.print("")
        Output.hint("To link a key again: sshwitch link --key <name>")
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
