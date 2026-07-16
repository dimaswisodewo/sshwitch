import ArgumentParser
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the global default and any repository override.",
        discussion: """
        Reports which key SSH is configured to try and which key Git will use
        for the selected repository. Repository overrides take precedence.

        Examples:
          sshwitch status
          sshwitch status --path ~/code/project
          sshwitch status --verbose
        """
    )

    @Option(name: .long, help: "Repository to inspect; defaults to the current directory.")
    var path: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        output.apply()
        let config = SSHConfig()
        let state = try config.readState()
        Output.print("SSH key selection")
        Output.print("")

        if let key = state.keyPath {
            Output.print("Global default: \(URL(fileURLWithPath: key).lastPathComponent)")
            Output.print("  Key:   \(key)")
            Output.print("  Hosts: \(state.hosts.joined(separator: ", "))")
            Output.detail("Included from: ~/.ssh/sshwitch.conf")
            if !state.includeInstalled { Output.warn("~/.ssh/config does not include the managed sshwitch configuration.") }
            for host in state.hosts {
                if let effective = config.effectiveState(for: host) {
                    Output.detail("\(host): IdentitiesOnly=\(effective.identitiesOnly ? "yes" : "no"), identities=\(effective.identityFiles.joined(separator: ", "))")
                    if effective.identityFiles.count > 1 { Output.warn("\(host) has additional fallback identities configured.") }
                }
            }
        } else {
            Output.print("Global default: off")
            if !state.hosts.isEmpty { Output.print("  Remembered hosts: \(state.hosts.joined(separator: ", "))") }
            Output.hint("Choose one: sshwitch switch --key <name> --host <hostname>")
        }

        let repoPath = try RepositoryState.resolvedPath(path)
        Output.print("")
        if !RepositoryState.isGitRepository(at: repoPath) {
            Output.print("Repository override: not checked (not a Git repository)")
            return
        }
        if let command = RepositoryState.localSSHCommand(at: repoPath) {
            let key = RepositoryState.keyPath(from: command)
            Output.print("Repository override: \(key.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "custom SSH command")")
            if let key { Output.print("  Key: \(key)") }
            Output.print("  Effective result: this repository override wins")
            Output.detail("core.sshCommand: \(command)")
            Output.hint("Use the global default here: sshwitch unlink --path \(repoPath)")
        } else if let host = RepositoryState.remoteHost(at: repoPath), state.hosts.contains(host), let key = state.keyPath {
            Output.print("Repository override: none")
            Output.print("  Effective result: '\(URL(fileURLWithPath: key).lastPathComponent)' via the global default for \(host)")
        } else {
            Output.print("Repository override: none")
            Output.print("  Effective result: standard SSH key resolution")
        }
    }
}
