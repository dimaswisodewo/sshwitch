import ArgumentParser

@main
struct Sshwitch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sshwitch",
        abstract: "Choose which SSH key Git and SSH use.",
        discussion: """
        WORKFLOWS
          Create a key
            sshwitch gen --name work --email you@company.com
            sshwitch add --key work

          Choose a global default for selected hosts
            sshwitch switch --key work --host github.com
            sshwitch status

          Override one repository
            sshwitch link --key personal
            sshwitch unlink

          Inspect and troubleshoot
            sshwitch list
            sshwitch doctor

        A repository override takes precedence over the global default.
        Use --dry-run to preview write operations and --verbose for technical details.
        """,
        version: "1.1.0",
        subcommands: [Gen.self, Add.self, SwitchCommand.self, Status.self, Link.self, Unlink.self, List.self, Doctor.self]
    )

    mutating func run() throws {
        throw CleanExit.helpRequest(self)
    }
}
