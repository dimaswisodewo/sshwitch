import Foundation

struct ShellResult {
    let output: String
    let exitCode: Int32
    var succeeded: Bool { exitCode == 0 }
}

enum Shell {
    /// Runs a command with explicit arguments (no shell interpolation — safe from injection).
    @discardableResult
    static func run(_ executable: String, arguments: [String] = []) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellResult(output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                           exitCode: process.terminationStatus)
    }
}
