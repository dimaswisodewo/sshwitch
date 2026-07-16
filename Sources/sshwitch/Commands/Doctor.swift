import ArgumentParser
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check SSH permissions, configuration, precedence, and connectivity.",
        discussion: """
        Checks ~/.ssh permissions, private keys, the managed global default,
        effective OpenSSH identities, and the current repository's SSH access.

        Examples:
          sshwitch doctor
          sshwitch doctor --verbose

        Failed checks produce suggested fixes and a nonzero exit status.
        """
    )

    @OptionGroup var output: OutputOptions

    func run() throws {
        output.apply()
        var passed = true
        Output.print("SSH setup diagnostics")

        Output.print("")
        Output.info("Checking ~/.ssh directory permissions...")
        passed = checkSSHDirectory() && passed

        Output.print("")
        Output.info("Checking private key permissions...")
        passed = checkKeys() && passed

        Output.print("")
        Output.info("Checking the global sshwitch configuration...")
        passed = checkGlobalConfiguration() && passed

        Output.print("")
        Output.info("Checking the effective key for this repository...")
        passed = checkRepositoryConnectivity() && passed

        Output.print("")
        if passed {
            Output.success("All checks passed.")
        } else {
            Output.warn("Some checks failed. Follow the suggested fixes above.")
            throw ExitCode.failure
        }
    }

    private func checkSSHDirectory() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh").path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let permissions = attributes[.posixPermissions] as? Int else {
            result("~/.ssh permissions", false, "directory not found; try: mkdir -m 700 ~/.ssh")
            return false
        }
        let actual = permissions & 0o777
        let valid = actual == 0o700
        result("~/.ssh permissions", valid, valid ? "700" : "expected 700, got \(String(format: "%o", actual)); try: chmod 700 ~/.ssh")
        return valid
    }

    private func checkKeys() -> Bool {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                           options: .skipsHiddenFiles) else {
            result("Private key permissions", false, "could not read ~/.ssh")
            return false
        }
        let publicNames = Set(contents.filter { $0.pathExtension == "pub" }.map { $0.deletingPathExtension().lastPathComponent })
        let keys = contents.filter { $0.pathExtension != "pub" && publicNames.contains($0.lastPathComponent) }
        if keys.isEmpty { Output.print("  [SKIP] No private/public key pairs found."); return true }
        var allValid = true
        for key in keys {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: key.path),
                  let permissions = attributes[.posixPermissions] as? Int else { continue }
            let actual = permissions & 0o777
            let valid = actual == 0o600
            result("\(key.lastPathComponent) permissions", valid,
                   valid ? "600" : "expected 600, got \(String(format: "%o", actual)); try: chmod 600 \(key.path)")
            allValid = valid && allValid
        }
        return allValid
    }

    private func checkGlobalConfiguration() -> Bool {
        let config = SSHConfig()
        guard let state = try? config.readState() else {
            result("Global configuration", false, "could not read SSH configuration")
            return false
        }
        guard let selected = state.keyPath else {
            Output.print("  [SKIP] Global default is off. Use: sshwitch switch --key <name> --host <hostname>")
            return true
        }
        guard state.includeInstalled else {
            result("Global configuration", false, "~/.ssh/config does not include ~/.ssh/sshwitch.conf")
            return false
        }
        var allValid = true
        for host in state.hosts {
            guard let effective = config.effectiveState(for: host) else {
                result("Global configuration for \(host)", false, "ssh -G validation failed")
                allValid = false
                continue
            }
            let selectedPath = URL(fileURLWithPath: selected).standardized.path
            let identities = effective.identityFiles.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardized.path
            }
            let valid = identities.first == selectedPath && effective.identitiesOnly
            result("Global configuration for \(host)", valid,
                   valid ? "selected key is first; IdentitiesOnly=yes" : "selected key is not effective as expected")
            if identities.count > 1 { Output.warn("  \(host) has \(identities.count - 1) additional fallback identity file(s).") }
            allValid = valid && allValid
        }
        return allValid
    }

    private func checkRepositoryConnectivity() -> Bool {
        let path = FileManager.default.currentDirectoryPath
        guard RepositoryState.isGitRepository(at: path) else {
            Output.print("  [SKIP] Current directory is not a Git repository.")
            return true
        }
        guard let host = RepositoryState.remoteHost(at: path) else {
            Output.print("  [SKIP] Repository has no SSH origin remote.")
            return true
        }

        let keyPath: String
        let source: String
        if let command = RepositoryState.localSSHCommand(at: path) {
            guard let parsed = RepositoryState.keyPath(from: command) else {
                result("Repository override", false, "could not parse core.sshCommand: \(command)")
                return false
            }
            keyPath = parsed
            source = "repository override"
        } else if let state = try? SSHConfig().readState(), state.hosts.contains(host), let selected = state.keyPath {
            keyPath = selected
            source = "global default"
        } else {
            Output.print("  [SKIP] No sshwitch key applies to \(host).")
            return true
        }

        Output.detail("Using \(source): \(keyPath)")
        guard let response = try? Shell.run("/usr/bin/ssh", arguments: [
            "-T", "-i", keyPath, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=accept-new", "git@\(host)"
        ]) else {
            result("SSH connectivity to \(host)", false, "could not launch ssh")
            return false
        }
        let reachable = response.exitCode == 0 || response.exitCode == 1
        result("SSH connectivity to \(host)", reachable,
               reachable ? "authenticated using \(source)" : "failed with exit \(response.exitCode); check the key, host, and network")
        Output.detail(response.errorOutput)
        return reachable
    }

    private func result(_ label: String, _ passed: Bool, _ detail: String) {
        let status = passed ? Output.colored("PASS", .green) : Output.colored("FAIL", .red)
        Output.print("  [\(status)] \(label): \(detail)")
    }
}
