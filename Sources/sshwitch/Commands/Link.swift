import ArgumentParser
import Foundation

struct Link: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Override the SSH key used by one Git repository.",
        discussion: """
        Examples:
          sshwitch link --key work
          sshwitch link --key personal --path ~/code/myrepo
          sshwitch link --key work --dry-run

        Use this when one repository should ignore the global default. Under the
        hood this sets Git's local core.sshCommand; remote URLs are not changed.
        """
    )

    @Option(name: .long, help: "Key name (e.g., work) or absolute path to private key.")
    var key: String

    @Option(name: .long, help: "Path to the git repository (defaults to current directory).")
    var path: String?

    @Flag(name: .long, help: "Print intended actions without executing them.")
    var dryRun: Bool = false

    @OptionGroup var output: OutputOptions

    func run() throws {
        output.apply()
        let repoPath = try RepositoryState.resolvedPath(path)
        let keyPath = try KeyResolver.resolve(key)
        let sshCommand = "ssh -i \(keyPath) -o IdentitiesOnly=yes"

        if dryRun {
            Output.print("Would create a repository override:")
            Output.print("  Repository: \(repoPath)")
            Output.print("  Key:        \(keyPath)")
            Output.detail("Command: git config core.sshCommand \"\(sshCommand)\"")
            Output.print("")
            Output.print("No changes were made.")
            return
        }

        // Step 1: Validate repo
        Output.step(1, of: 2, "Validating git repository at '\(repoPath)'...")
        try RepositoryState.requireGitRepository(at: repoPath)

        // Step 2: Set git config
        Output.step(2, of: 2, "Linking key '\(keyPath)' to repo...")
        let result = try Shell.run("/usr/bin/git", arguments: [
            "-C", repoPath,
            "config", "core.sshCommand", sshCommand
        ])

        guard result.succeeded else {
            throw RuntimeError("Git could not create the repository override (exit \(result.exitCode)). \(result.errorOutput)")
        }

        Output.print("")
        Output.success("Repository override set to '\(URL(fileURLWithPath: keyPath).lastPathComponent)'.")
        Output.print("  Repository: \(repoPath)")
        Output.print("  Key:        \(keyPath)")
        Output.detail("core.sshCommand: \(sshCommand)")
        Output.print("")
        Output.hint("Check the effective key: sshwitch status --path \(repoPath)")
    }
}
