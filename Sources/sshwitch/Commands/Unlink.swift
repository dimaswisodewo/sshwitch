import ArgumentParser
import Foundation

struct Unlink: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a repository override and return to global SSH behavior.",
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

    @OptionGroup var output: OutputOptions

    func run() throws {
        output.apply()
        let repoPath = try RepositoryState.resolvedPath(path)

        // Step 1: Validate repo
        Output.step(1, of: 2, "Validating git repository at '\(repoPath)'...")
        try RepositoryState.requireGitRepository(at: repoPath)

        // Step 2: Read current link
        let current = try Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "config", "core.sshCommand"])
        guard current.succeeded, !current.output.isEmpty else {
            Output.warn("No repository override is configured for '\(repoPath)'.")
            Output.hint("Check the effective key: sshwitch status --path \(repoPath)")
            return
        }

        Output.print("")
        Output.print("Currently linked: \(Output.colored(current.output, .bold))")
        Output.print("")

        if dryRun {
            Output.print("Would remove the repository override:")
            Output.print("  Repository: \(repoPath)")
            Output.print("  Current:    \(current.output)")
            Output.detail("Command: git config --unset core.sshCommand")
            Output.print("")
            Output.print("No changes were made.")
            return
        }

        // Step 3: Unset
        Output.step(2, of: 2, "Unlinking SSH key from repo...")
        let result = try Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "config", "--unset", "core.sshCommand"])
        guard result.succeeded else {
            throw RuntimeError("Git could not remove the repository override (exit \(result.exitCode)). \(result.errorOutput)")
        }

        Output.print("")
        Output.success("Repository override removed.")
        Output.print("  Git will now use the matching global default or standard SSH key resolution.")
        Output.print("")
        Output.hint("Check the effective key: sshwitch status --path \(repoPath)")
    }
}
