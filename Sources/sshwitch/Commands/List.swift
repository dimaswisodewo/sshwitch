import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available SSH keys and show where active keys apply.",
        discussion: """
        Examples:
          sshwitch list

        Shows key pairs found in ~/.ssh. The ACTIVE column distinguishes the
        global default from a key overriding the current Git repository.
        """
    )

    @OptionGroup var output: OutputOptions

    func run() throws {
        output.apply()
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

        guard FileManager.default.fileExists(atPath: sshDir.path) else {
            throw RuntimeError("~/.ssh directory not found.")
        }

        let keys = try discoverKeys(in: sshDir)

        if keys.isEmpty {
            Output.info("No SSH keys found in \(sshDir.path).")
            Output.print("")
            Output.hint("Get started by generating your first key:")
            Output.hint("  sshwitch gen --name <name> --email <email>")
            Output.print("")
            Output.hint("Example:")
            Output.hint("  sshwitch gen --name work --email you@company.com")
            return
        }

        let globalPath = (try? SSHConfig().readState())?.keyPath
        let localPath = RepositoryState.localSSHCommand(at: FileManager.default.currentDirectoryPath)
            .flatMap(RepositoryState.keyPath)
        let header = String(format: "%-26@ %-11@ %-12@ %@", "NAME", "TYPE", "CREATED", "ACTIVE")
        Output.print(Output.colored(header, .bold))
        Output.print(String(repeating: "-", count: 72))

        for key in keys {
            let keyPath = sshDir.appendingPathComponent(key.name).path
            var active: [String] = []
            if globalPath == keyPath { active.append("global") }
            if localPath == keyPath { active.append("repository") }
            Output.print(String(format: "%-26@ %-11@ %-12@ %@", key.name, key.keyType, key.created,
                                active.isEmpty ? "—" : active.joined(separator: ", ")))
        }
        Output.print("")
        Output.hint("See precedence and hosts: sshwitch status")
    }

    // MARK: - Helpers

    struct KeyInfo {
        let name: String
        let keyType: String
        let created: String
    }

    private func discoverKeys(in sshDir: URL) throws -> [KeyInfo] {
        let contents = try FileManager.default.contentsOfDirectory(at: sshDir,
                                                                    includingPropertiesForKeys: [.creationDateKey],
                                                                    options: .skipsHiddenFiles)
        let pubKeys = Set(contents.filter { $0.pathExtension == "pub" }.map { $0.deletingPathExtension().lastPathComponent })

        var result: [KeyInfo] = []
        for url in contents where url.pathExtension != "pub" && pubKeys.contains(url.lastPathComponent) {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let created: String
            if let date = attrs[.creationDate] as? Date {
                let fmt = DateFormatter()
                fmt.dateStyle = .short
                created = fmt.string(from: date)
            } else {
                created = "unknown"
            }

            // Read key type from the .pub file's first token
            let pubPath = url.appendingPathExtension("pub").path
            let keyType: String
            if let pubContent = try? String(contentsOfFile: pubPath, encoding: .utf8),
               let firstToken = pubContent.split(separator: " ").first {
                keyType = String(firstToken)
                    .replacingOccurrences(of: "ssh-", with: "")
                    .replacingOccurrences(of: "ecdsa-", with: "")
            } else {
                keyType = "unknown"
            }

            result.append(KeyInfo(name: url.lastPathComponent, keyType: keyType, created: created))
        }
        return result.sorted { $0.name < $1.name }
    }
}
