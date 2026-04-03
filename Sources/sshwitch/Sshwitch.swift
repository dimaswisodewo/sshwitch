import ArgumentParser

@main
struct Sshwitch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sshwitch",
        abstract: "Manage SSH keys for Git repositories.",
        discussion: """
        Quick start:
          1. Generate a key:    sshwitch gen --name work --email you@company.com
          2. Add to agent:      sshwitch gen --name work --email you@company.com --add-to-agent
          3. Link to a repo:    cd ~/code/myrepo && sshwitch link --key work
          4. Verify setup:      sshwitch doctor
          5. List your keys:    sshwitch list
          6. Unlink a repo:     cd ~/code/myrepo && sshwitch unlink

        Use --dry-run with gen, link, or unlink to preview changes before applying them.
        """,
        version: "0.1.0",
        subcommands: [Gen.self, Link.self, Unlink.self, List.self, Doctor.self]
    )
}
