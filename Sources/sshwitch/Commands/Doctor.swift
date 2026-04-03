import ArgumentParser
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run diagnostics on SSH configuration and connectivity.",
        discussion: """
        Examples:
          sshwitch doctor

        Checks:
          - ~/.ssh directory permissions (must be 700 so other users can't read your keys)
          - Private key file permissions (must be 600 or SSH will refuse to use the key)
          - SSH connectivity using the key linked to the current repository (if any)
        """
    )

    func run() throws {
        var allPassed = true

        Output.print("sshwitch doctor — running checks...\n")

        // Check 1: ~/.ssh permissions
        Output.info("Checking ~/.ssh directory permissions (must be 700)...")
        allPassed = checkSshDirPermissions() && allPassed

        // Check 2: Key file permissions
        Output.print("")
        Output.info("Checking private key file permissions (must be 600)...")
        allPassed = checkKeyPermissions() && allPassed

        // Check 3: SSH connectivity using the linked key
        Output.print("")
        Output.info("Checking SSH connectivity using the linked key...")
        let repoPath = FileManager.default.currentDirectoryPath
        allPassed = checkLinkedConnectivity(repoPath: repoPath) && allPassed

        Output.print("")
        if allPassed {
            Output.success("All checks passed.")
        } else {
            Output.warn("Some checks failed. Review the issues above.")
        }
    }

    // MARK: - Checks

    @discardableResult
    private func checkSshDirPermissions() -> Bool {
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh").path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: sshDir),
              let posixPerms = attrs[.posixPermissions] as? Int else {
            printResult(label: "~/.ssh permissions", passed: false, detail: "Directory not found")
            return false
        }
        let passed = (posixPerms & 0o777) == 0o700
        printResult(label: "~/.ssh permissions", passed: passed,
                    detail: passed ? "700 ✓" : "Expected 700, got \(String(format: "%o", posixPerms & 0o777)). Fix: chmod 700 ~/.ssh")
        return passed
    }

    @discardableResult
    private func checkKeyPermissions() -> Bool {
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: sshDir,
                                                                           includingPropertiesForKeys: nil,
                                                                           options: .skipsHiddenFiles) else {
            printResult(label: "Key permissions", passed: false, detail: "Could not read ~/.ssh")
            return false
        }

        let pubKeys = Set(contents.filter { $0.pathExtension == "pub" }.map { $0.deletingPathExtension().lastPathComponent })
        let privateKeys = contents.filter { $0.pathExtension != "pub" && pubKeys.contains($0.lastPathComponent) }

        var allPassed = true
        for keyURL in privateKeys {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: keyURL.path),
                  let perms = attrs[.posixPermissions] as? Int else { continue }
            let passed = (perms & 0o777) == 0o600
            printResult(label: "  \(keyURL.lastPathComponent) permissions", passed: passed,
                        detail: passed ? "600 ✓" : "Expected 600, got \(String(format: "%o", perms & 0o777)). Fix: chmod 600 \(keyURL.path)")
            allPassed = allPassed && passed
        }

        if privateKeys.isEmpty {
            Output.print("  [skip] No private keys found in ~/.ssh")
        }
        return allPassed
    }

    @discardableResult
    private func checkLinkedConnectivity(repoPath: String) -> Bool {
        // Check if we're in a git repo
        guard let repoCheck = try? Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "rev-parse", "--git-dir"]),
              repoCheck.succeeded else {
            Output.print("  [skip] Not inside a git repository.")
            return true
        }

        // Read core.sshCommand
        guard let sshCmdResult = try? Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "config", "core.sshCommand"]),
              sshCmdResult.succeeded, !sshCmdResult.output.isEmpty else {
            Output.print("  [skip] No SSH key linked to this repository. Run: sshwitch link --key <name>")
            return true
        }

        let sshCommand = sshCmdResult.output

        // Parse the key path from "ssh -i <path> -o IdentitiesOnly=yes"
        guard let keyPath = parseKeyPath(from: sshCommand) else {
            printResult(label: "Linked key connectivity", passed: false,
                        detail: "Could not parse key path from core.sshCommand: \(sshCommand)")
            return false
        }

        // Parse the remote host
        guard let (host, label) = parseRemoteHost(repoPath: repoPath) else {
            Output.print("  [skip] No SSH remote found in this repository.")
            return true
        }

        return checkConnectivity(keyPath: keyPath, host: host, label: label)
    }

    @discardableResult
    private func checkConnectivity(keyPath: String, host: String, label: String) -> Bool {
        guard let result = try? Shell.run("/usr/bin/ssh", arguments: [
            "-T",
            "-i", keyPath,
            "-o", "IdentitiesOnly=yes",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            "git@\(host)"
        ]) else {
            printResult(label: "\(label) SSH connectivity", passed: false, detail: "Failed to launch ssh")
            return false
        }

        // GitHub/GitLab return exit code 1 on successful auth (no PTY/shell), 255 on failure
        let passed = result.exitCode == 1 || result.exitCode == 0
        printResult(label: "\(label) SSH connectivity (\(keyPath))", passed: passed,
                    detail: passed ? "reachable ✓" : "unreachable (exit \(result.exitCode)) — check key or network")
        return passed
    }

    // MARK: - Helpers

    /// Extracts the key path from a core.sshCommand value like "ssh -i /path/to/key -o IdentitiesOnly=yes"
    private func parseKeyPath(from sshCommand: String) -> String? {
        let parts = sshCommand.components(separatedBy: .whitespaces)
        guard let iIndex = parts.firstIndex(of: "-i"), parts.indices.contains(iIndex + 1) else {
            return nil
        }
        return parts[iIndex + 1]
    }

    /// Reads git remotes and returns the SSH hostname and a human-readable label.
    /// Handles SSH URLs like git@github.com:user/repo.git
    private func parseRemoteHost(repoPath: String) -> (host: String, label: String)? {
        guard let result = try? Shell.run("/usr/bin/git", arguments: ["-C", repoPath, "remote", "-v"]),
              result.succeeded, !result.output.isEmpty else {
            return nil
        }

        for line in result.output.components(separatedBy: .newlines) {
            // Match SSH remote URLs: git@hostname:user/repo.git
            // e.g. "origin	git@github.com:user/repo.git (fetch)"
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let url = parts[1]
            if url.hasPrefix("git@") {
                // git@github.com:user/repo.git → github.com
                let withoutPrefix = String(url.dropFirst(4)) // drop "git@"
                if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                    let host = String(withoutPrefix[withoutPrefix.startIndex..<colonIndex])
                    let label = host.components(separatedBy: ".").first.map { $0.capitalized } ?? host
                    return (host, label)
                }
            }
        }
        return nil
    }

    private func printResult(label: String, passed: Bool, detail: String) {
        let status = passed
            ? Output.colored("PASS", .green)
            : Output.colored("FAIL", .red)
        Output.print("[\(status)] \(label): \(detail)")
    }
}
