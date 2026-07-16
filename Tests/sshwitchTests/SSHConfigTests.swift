import Foundation
import XCTest
@testable import sshwitch

final class SSHConfigTests: XCTestCase {
    func testCreatesManagedIncludeAndRemembersState() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let key = home.appendingPathComponent(".ssh/work").path
        try Data().write(to: URL(fileURLWithPath: key))

        let config = SSHConfig(homeDirectory: home)
        try config.activate(keyPath: key, hosts: ["github.com", "gitlab.com"], dryRun: false)

        let main = try String(contentsOf: home.appendingPathComponent(".ssh/config"), encoding: .utf8)
        let managed = try String(contentsOf: home.appendingPathComponent(".ssh/sshwitch.conf"), encoding: .utf8)
        let state = try config.readState()
        XCTAssertTrue(main.hasPrefix("Include ~/.ssh/sshwitch.conf"))
        XCTAssertTrue(managed.contains("Host github.com gitlab.com"))
        XCTAssertTrue(managed.contains("IdentitiesOnly yes"))
        XCTAssertEqual(state.keyPath, key)
        XCTAssertEqual(state.hosts, ["github.com", "gitlab.com"])
        XCTAssertTrue(state.includeInstalled)
    }

    func testPreservesExistingConfigAndCreatesBackup() throws {
        let home = try temporaryHome(config: "Host server.example\n  User alice\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let config = SSHConfig(homeDirectory: home)
        try config.activate(keyPath: home.appendingPathComponent(".ssh/work").path,
                            hosts: ["github.com"], dryRun: false)

        let main = try String(contentsOf: home.appendingPathComponent(".ssh/config"), encoding: .utf8)
        let files = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".ssh").path)
        XCTAssertTrue(main.contains("Host server.example"))
        XCTAssertTrue(files.contains(where: { $0.contains("config.sshwitch-backup-") }))
    }

    func testDeactivationKeepsRememberedHosts() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = SSHConfig(homeDirectory: home)
        try config.activate(keyPath: home.appendingPathComponent(".ssh/work").path,
                            hosts: ["github.com"], dryRun: false)
        let hosts = try config.deactivate(dryRun: false)
        let state = try config.readState()
        XCTAssertEqual(hosts, ["github.com"])
        XCTAssertNil(state.keyPath)
        XCTAssertEqual(state.hosts, ["github.com"])
    }

    func testRepeatedSwitchIsIdempotent() throws {
        let home = try temporaryHome(config: "Host server.example\n  User alice\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let config = SSHConfig(homeDirectory: home)
        try config.activate(keyPath: home.appendingPathComponent(".ssh/work").path,
                            hosts: ["github.com"], dryRun: false)
        try config.activate(keyPath: home.appendingPathComponent(".ssh/personal").path,
                            hosts: ["github.com"], dryRun: false)

        let main = try String(contentsOf: home.appendingPathComponent(".ssh/config"), encoding: .utf8)
        XCTAssertEqual(main.components(separatedBy: "Include ~/.ssh/sshwitch.conf").count - 1, 1)
        XCTAssertEqual(try config.readState().keyPath, home.appendingPathComponent(".ssh/personal").path)
    }

    func testDryRunDoesNotWriteConfiguration() throws {
        let home = try temporaryHome(config: "Host server.example\n  User alice\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let original = try String(contentsOf: home.appendingPathComponent(".ssh/config"), encoding: .utf8)
        try SSHConfig(homeDirectory: home).activate(keyPath: home.appendingPathComponent(".ssh/work").path,
                                                   hosts: ["github.com"], dryRun: true)
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".ssh/config"), encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".ssh/sshwitch.conf").path))
    }

    func testPreservesConfigSymlink() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent("dotfiles/ssh-config")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Host server.example\n  User alice\n".write(to: target, atomically: true, encoding: .utf8)
        let link = home.appendingPathComponent(".ssh/config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try SSHConfig(homeDirectory: home).activate(keyPath: home.appendingPathComponent(".ssh/work").path,
                                                   hosts: ["github.com"], dryRun: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).hasPrefix("Include ~/.ssh/sshwitch.conf"))
    }

    func testRefusesUnownedManagedFile() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try "Host *\n".write(to: home.appendingPathComponent(".ssh/sshwitch.conf"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(
            try SSHConfig(homeDirectory: home).activate(
                keyPath: home.appendingPathComponent(".ssh/work").path,
                hosts: ["github.com"], dryRun: false
            )
        ) { error in XCTAssertTrue(error is RuntimeError) }
    }

    func testRejectsUnsafeHosts() {
        for host in ["", "*.example.com", "!github.com", "two hosts", "bad\nname"] {
            XCTAssertThrowsError(try SSHConfig.validateHost(host))
        }
    }

    private func temporaryHome(config: String? = nil) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sshwitch-tests-\(UUID().uuidString)")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if let config {
            try config.write(to: ssh.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        }
        return home
    }
}
