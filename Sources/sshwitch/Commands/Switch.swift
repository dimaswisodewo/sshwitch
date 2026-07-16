import ArgumentParser
import Foundation

struct SwitchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switch",
        abstract: "Choose the global default key for selected SSH hosts.",
        discussion: """
        Use this when the same key should be the default across repositories.
        Hosts are remembered, so --host is only required the first time.

        Examples:
          sshwitch switch --key work --host github.com --host gitlab.com
          sshwitch switch --key personal
          sshwitch switch --off
          sshwitch switch --key work --dry-run

        Under the hood, sshwitch manages ~/.ssh/sshwitch.conf and includes it
        from ~/.ssh/config. A repository configured by `sshwitch link` still wins.
        """
    )

    @Option(name: .long, help: "Key name or path to make the global default.")
    var key: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Literal SSH host to configure; repeat for multiple hosts.")
    var host: [String] = []

    @Flag(name: .long, help: "Disable the global default while remembering its hosts.")
    var off = false

    @Flag(name: .long, help: "Show intended changes without writing files.")
    var dryRun = false

    @OptionGroup var output: OutputOptions

    mutating func validate() throws {
        if off && key != nil { throw ValidationError("Use either --key or --off, not both.") }
        if off && !host.isEmpty { throw ValidationError("--host cannot be used with --off.") }
        if !off && key == nil { throw ValidationError("Provide --key <name>, or use --off.") }
        for value in host { try SSHConfig.validateHost(value) }
    }

    func run() throws {
        output.apply()
        let config = SSHConfig()

        if off {
            let remembered = try config.deactivate(dryRun: dryRun)
            guard !remembered.isEmpty else {
                Output.warn("No global default is configured.")
                Output.hint("Choose one: sshwitch switch --key <name> --host <hostname>")
                return
            }
            guard !dryRun else { return }
            Output.success("Global default disabled.")
            Output.print("  Remembered hosts: \(remembered.joined(separator: ", "))")
            Output.print("")
            Output.hint("Choose another key: sshwitch switch --key <name>")
            return
        }

        let state = try config.readState()
        let hosts = host.isEmpty ? state.hosts : host.reduce(into: [String]()) { values, item in
            if !values.contains(item) { values.append(item) }
        }
        guard !hosts.isEmpty else {
            throw ValidationError("No hosts are configured yet. Add one with --host, for example: --host github.com")
        }
        let keyPath = try KeyResolver.resolve(key!)
        try config.activate(keyPath: keyPath, hosts: hosts, dryRun: dryRun)
        guard !dryRun else { return }

        Output.success("Global default changed to '\(URL(fileURLWithPath: keyPath).lastPathComponent)'.")
        Output.print("  Hosts: \(hosts.joined(separator: ", "))")
        Output.print("  Key:   \(keyPath)")
        printIdentityWarnings(config: config, hosts: hosts, keyPath: keyPath)

        let currentPath = FileManager.default.currentDirectoryPath
        if let local = RepositoryState.localSSHCommand(at: currentPath) {
            let localKey = RepositoryState.keyPath(from: local) ?? local
            Output.print("")
            Output.warn("This repository still uses '\(URL(fileURLWithPath: localKey).lastPathComponent)'.")
            Output.print("  Repository overrides take precedence over the global default.")
            Output.hint("To use the global default here: sshwitch unlink")
        } else {
            Output.print("")
            Output.hint("Check the active configuration: sshwitch status")
        }
    }

    private func printIdentityWarnings(config: SSHConfig, hosts: [String], keyPath: String) {
        for value in hosts {
            guard let effective = config.effectiveState(for: value) else { continue }
            let selected = URL(fileURLWithPath: keyPath).standardized.path
            let extras = effective.identityFiles.filter {
                let expanded = ($0 as NSString).expandingTildeInPath
                return URL(fileURLWithPath: expanded).standardized.path != selected
            }
            if !extras.isEmpty {
                Output.warn("\(value) has \(extras.count) additional configured identity file(s).")
                Output.detail("Fallback identities: \(extras.joined(separator: ", "))")
            }
        }
    }
}
