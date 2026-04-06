import ArgumentParser
import Foundation

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add an existing SSH key to the SSH agent.",
        discussion: """
        Examples:
          sshwitch add --key work
          sshwitch add --key ~/.ssh/personal

        Runs ssh-add to load the private key into the running SSH agent so it
        is available for Git operations and SSH connections.
        """
    )

    @Option(name: .long, help: "Key name (e.g., work) or absolute path to private key.")
    var key: String

    func run() throws {
        // Step 1: Resolve key path
        Output.step(1, of: 2, "Resolving key '\(key)'...")
        let keyPath = try KeyResolver.resolve(key)

        // Step 2: Add to agent
        Output.step(2, of: 2, "Adding key to SSH agent...")
        let result = try Shell.run("/usr/bin/ssh-add", arguments: [keyPath])

        guard result.succeeded else {
            throw RuntimeError("ssh-add failed (exit \(result.exitCode)). Is the SSH agent running?")
        }

        Output.print("")
        Output.success("Key '\(keyPath)' added to the SSH agent.")
    }
}
