import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List SSH keys in ~/.ssh managed by sshwitch.",
        discussion: """
        Examples:
          sshwitch list

        Shows all SSH key pairs found in ~/.ssh (files with a matching .pub file).
        """
    )

    func run() throws {
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

        let header = String(format: "%-30@ %-12@ %@", "NAME", "TYPE", "CREATED")
        Output.print(Output.colored(header, .bold))
        Output.print(String(repeating: "-", count: 60))

        for key in keys {
            Output.print(String(format: "%-30@ %-12@ %@", key.name, key.keyType, key.created))
        }
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
