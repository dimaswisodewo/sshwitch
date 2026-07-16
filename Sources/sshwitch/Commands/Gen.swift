import ArgumentParser
import Foundation

struct Gen: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a new SSH key and optionally add it to the SSH agent.",
        discussion: """
        Examples:
          sshwitch gen --name work --email alice@company.com
          sshwitch gen --name personal --email alice@gmail.com --add-to-agent
          sshwitch gen --name work --email alice@company.com --dry-run

        The key is saved to ~/.ssh/<name> (private) and ~/.ssh/<name>.pub (public).
        Use --add-to-agent so the key is immediately usable without a manual ssh-add.
        After generating, add the public key to GitHub/GitLab under Settings > SSH Keys.
        """
    )

    @Option(name: .long, help: "Name for the key file (stored as ~/.ssh/<name>).")
    var name: String

    @Option(name: .long, help: "Email address to use as the key comment.")
    var email: String

    @Flag(name: .long, help: "Add the generated key to the SSH agent.")
    var addToAgent: Bool = false

    @Flag(name: .long, help: "Print intended actions without executing them.")
    var dryRun: Bool = false

    @OptionGroup var output: OutputOptions

    func run() throws {
        output.apply()
        guard !name.isEmpty, !name.contains("/") else {
            throw ValidationError("--name must be a plain filename with no path separators.")
        }

        let sshDir = try sshDirectory()
        let keyPath = sshDir.appendingPathComponent(name).path
        let totalSteps = addToAgent ? 3 : 2

        if dryRun {
            Output.print("Would generate an ed25519 SSH key:")
            Output.print("  Private key: \(keyPath)")
            Output.print("  Public key:  \(keyPath).pub")
            Output.detail("Command: ssh-keygen -t ed25519 -C \"\(email)\" -f \(keyPath) -N \"\"")
            Output.detail("Permissions: 600")
            if addToAgent {
                Output.print("  Add to agent: yes")
                Output.detail("Command: ssh-add \(keyPath)")
            }
            Output.print("")
            Output.print("No changes were made.")
            return
        }

        // Step 1: Generate key
        Output.step(1, of: totalSteps, "Generating ed25519 key '\(name)'...")
        let result = try Shell.run("/usr/bin/ssh-keygen", arguments: [
            "-t", "ed25519",
            "-C", email,
            "-f", keyPath,
            "-N", ""
        ])

        guard result.succeeded else {
            throw RuntimeError("ssh-keygen failed (exit \(result.exitCode)). \(result.errorOutput)")
        }

        // Step 2: Set permissions
        Output.step(2, of: totalSteps, "Saving key and setting secure permissions...")
        try setPermissions(path: keyPath, octal: 0o600)
        try setPermissions(path: keyPath + ".pub", octal: 0o600)

        // Step 3: Add to agent
        if addToAgent {
            Output.step(3, of: 3, "Adding key to SSH agent...")
            let addResult = try Shell.run("/usr/bin/ssh-add", arguments: [keyPath])
            if !addResult.succeeded {
                Output.error("ssh-add failed — key was generated but not added to the agent.")
            }
        }

        // Print public key
        let pubKeyPath = keyPath + ".pub"
        if let pubKey = try? String(contentsOfFile: pubKeyPath, encoding: .utf8) {
            Output.print("")
            Output.print("Public key (add this to GitHub/GitLab → Settings → SSH Keys):")
            Output.print(pubKey.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        Output.print("")
        Output.success("Key '\(name)' created successfully.")
        Output.print("")
        Output.hint("Next steps:")
        Output.hint("  1. Copy the public key above and add it to GitHub/GitLab")
        Output.hint("  2. Make it the global default: sshwitch switch --key \(name) --host github.com")
        Output.hint("  3. Or override one repository: sshwitch link --key \(name)")
        Output.hint("  4. Verify your setup:          sshwitch doctor")
    }

    // MARK: - Helpers

    private func sshDirectory() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sshDir = home.appendingPathComponent(".ssh")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sshDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw RuntimeError("~/.ssh directory does not exist. Create it with: mkdir -m 700 ~/.ssh")
        }
        return sshDir
    }

    private func setPermissions(path: String, octal: mode_t) throws {
        guard chmod(path, octal) == 0 else {
            throw RuntimeError("Failed to set permissions on \(path).")
        }
    }
}
