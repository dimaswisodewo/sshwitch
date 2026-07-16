import ArgumentParser
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct GlobalSSHState {
    let keyPath: String?
    let hosts: [String]
    let includeInstalled: Bool
}

struct EffectiveSSHState {
    let identityFiles: [String]
    let identitiesOnly: Bool
}

struct SSHConfig {
    static let marker = "# Managed by sshwitch. Changes may be overwritten."
    static let includeLine = "Include ~/.ssh/sshwitch.conf"

    let homeDirectory: URL
    private let fileManager = FileManager.default

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    private var sshDirectory: URL { homeDirectory.appendingPathComponent(".ssh") }
    private var configURL: URL { sshDirectory.appendingPathComponent("config") }
    private var managedURL: URL { sshDirectory.appendingPathComponent("sshwitch.conf") }

    func readState() throws -> GlobalSSHState {
        let managed = (try? String(contentsOf: managedURL, encoding: .utf8)) ?? ""
        let main = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let hosts = metadata(named: "hosts", in: managed)?.split(separator: " ").map(String.init) ?? []
        let key = metadata(named: "key", in: managed)
        return GlobalSSHState(keyPath: key, hosts: hosts, includeInstalled: containsManagedInclude(main))
    }

    func activate(keyPath: String, hosts: [String], dryRun: Bool) throws {
        try ensureSSHDirectory()
        try ensureManagedFileIsOwned()
        let managed = render(keyPath: keyPath, hosts: hosts)
        let originalMain = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let candidateMain = containsManagedInclude(originalMain)
            ? originalMain
            : Self.includeLine + (originalMain.isEmpty ? "\n" : "\n\n" + originalMain)
        try validate(mainConfig: candidateMain, managedConfig: managed, hosts: hosts)

        if dryRun {
            Output.print("Would set the global default SSH key:")
            Output.print("  Key:   \(displayPath(keyPath))")
            Output.print("  Hosts: \(hosts.joined(separator: ", "))")
            if !containsManagedInclude(originalMain) { Output.print("  Add:   \(Self.includeLine) to ~/.ssh/config") }
            Output.print("  Write: ~/.ssh/sshwitch.conf")
            Output.print("")
            Output.print("No changes were made.")
            return
        }

        if !containsManagedInclude(originalMain), fileManager.fileExists(atPath: configURL.path) {
            let backup = try backupURL()
            try fileManager.copyItem(at: resolvedConfigURL(), to: backup)
            Output.detail("Backup: \(backup.path)")
        }
        try atomicWrite(managed, to: managedURL)
        if !containsManagedInclude(originalMain) { try atomicWrite(candidateMain, to: resolvedConfigURL()) }
        Output.detail("Managed config: \(managedURL.path)")
        Output.detail("Validated with: ssh -G for \(hosts.joined(separator: ", "))")
    }

    func deactivate(dryRun: Bool) throws -> [String] {
        let state = try readState()
        guard !state.hosts.isEmpty || state.keyPath != nil else { return [] }
        let managed = render(keyPath: nil, hosts: state.hosts)
        let main = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if dryRun {
            Output.print("Would disable the global default SSH key.")
            Output.print("  Remembered hosts: \(state.hosts.joined(separator: ", "))")
            Output.print("")
            Output.print("No changes were made.")
            return state.hosts
        }
        try ensureManagedFileIsOwned()
        if !state.hosts.isEmpty { try validate(mainConfig: main, managedConfig: managed, hosts: state.hosts) }
        try atomicWrite(managed, to: managedURL)
        Output.detail("Cleared active identity in \(managedURL.path)")
        return state.hosts
    }

    func effectiveState(for host: String) -> EffectiveSSHState? {
        guard let result = try? Shell.run("/usr/bin/ssh", arguments: ["-G", host]), result.succeeded else { return nil }
        var identities: [String] = []
        var identitiesOnly = false
        for line in result.output.split(separator: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            if parts[0] == "identityfile" { identities.append(String(parts[1])) }
            if parts[0] == "identitiesonly" { identitiesOnly = parts[1] == "yes" }
        }
        return EffectiveSSHState(identityFiles: identities, identitiesOnly: identitiesOnly)
    }

    static func validateHost(_ host: String) throws {
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !host.isEmpty,
              host.rangeOfCharacter(from: forbidden) == nil,
              !host.contains("*"), !host.contains("?"), !host.hasPrefix("!"),
              host.allSatisfy({ $0.isLetter || $0.isNumber || ".:-_[]".contains($0) }) else {
            throw ValidationError("Invalid --host '\(host)'. Use a literal hostname or IP address without wildcards.")
        }
    }

    private func render(keyPath: String?, hosts: [String]) -> String {
        var lines = [Self.marker, "# sshwitch-hosts: \(hosts.joined(separator: " "))"]
        if let keyPath {
            lines.append("# sshwitch-key: \(keyPath)")
            lines.append("")
            lines.append("Host \(hosts.joined(separator: " "))")
            lines.append("  IdentityFile \(quoted(keyPath))")
            lines.append("  IdentitiesOnly yes")
        } else {
            lines.append("# Global default is disabled.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func validate(mainConfig: String, managedConfig: String, hosts: [String]) throws {
        let expanded = mainConfig
            .replacingOccurrences(of: Self.includeLine, with: managedConfig)
            .replacingOccurrences(of: "Include \(managedURL.path)", with: managedConfig)
        let temporary = sshDirectory.appendingPathComponent(".sshwitch-validation-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? fileManager.removeItem(at: temporary) }
        try atomicWrite(expanded, to: temporary)
        for host in hosts {
            let result = try Shell.run("/usr/bin/ssh", arguments: ["-G", "-F", temporary.path, host])
            guard result.succeeded else {
                throw RuntimeError("SSH rejected the proposed configuration for '\(host)': \(result.errorOutput)")
            }
        }
    }

    private func ensureSSHDirectory() throws {
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: sshDirectory.path, isDirectory: &directory), directory.boolValue else {
            throw RuntimeError("~/.ssh does not exist. Create it with: mkdir -m 700 ~/.ssh")
        }
    }

    private func ensureManagedFileIsOwned() throws {
        guard fileManager.fileExists(atPath: managedURL.path) else { return }
        let content = try String(contentsOf: managedURL, encoding: .utf8)
        guard content.hasPrefix(Self.marker) else {
            throw RuntimeError("~/.ssh/sshwitch.conf already exists but is not managed by sshwitch. Move or rename it first.")
        }
    }

    private func containsManagedInclude(_ content: String) -> Bool {
        content.split(separator: "\n").contains { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return value == Self.includeLine || value == "Include \(managedURL.path)"
        }
    }

    private func metadata(named name: String, in content: String) -> String? {
        let prefix = "# sshwitch-\(name): "
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
    }

    private func resolvedConfigURL() -> URL {
        guard fileManager.fileExists(atPath: configURL.path) else { return configURL }
        return configURL.resolvingSymlinksInPath()
    }

    private func backupURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = resolvedConfigURL().path + ".sshwitch-backup-" + formatter.string(from: Date())
        var candidate = base
        var index = 1
        while fileManager.fileExists(atPath: candidate) { candidate = "\(base)-\(index)"; index += 1 }
        return URL(fileURLWithPath: candidate)
    }

    private func atomicWrite(_ content: String, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp.\(ProcessInfo.processInfo.processIdentifier)")
        guard let data = content.data(using: .utf8) else { throw RuntimeError("Could not encode SSH configuration.") }
        try data.write(to: temporary, options: .atomic)
        guard chmod(temporary.path, 0o600) == 0 else { throw RuntimeError("Could not secure \(temporary.path).") }
        guard rename(temporary.path, destination.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw RuntimeError("Could not update \(destination.path).")
        }
    }

    private func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func displayPath(_ path: String) -> String {
        path.hasPrefix(homeDirectory.path + "/") ? "~/" + path.dropFirst(homeDirectory.path.count + 1) : path
    }
}
