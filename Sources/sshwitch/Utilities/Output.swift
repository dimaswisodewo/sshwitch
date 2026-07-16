import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum Output {

    nonisolated(unsafe) private static var verboseEnabled = false

    static func configure(verbose: Bool) {
        verboseEnabled = verbose
    }

    // MARK: - Color support

    enum ANSIColor: String {
        case red    = "\u{001B}[31m"
        case green  = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case bold   = "\u{001B}[1m"
        case reset  = "\u{001B}[0m"
    }

    private static var noColor: Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] != nil
    }

    private static var cliColorForce: Bool {
        ProcessInfo.processInfo.environment["CLICOLOR_FORCE"] != nil
    }

    private static var stdoutIsTTY: Bool {
        isatty(STDOUT_FILENO) != 0
    }

    private static var stderrIsTTY: Bool {
        isatty(STDERR_FILENO) != 0
    }

    static func colored(_ text: String, _ color: ANSIColor) -> String {
        guard !noColor, stdoutIsTTY || cliColorForce else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }

    private static func coloredOnStderr(_ text: String, _ color: ANSIColor) -> String {
        guard !noColor, stderrIsTTY || cliColorForce else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }

    // MARK: - Output methods

    static func print(_ message: String) {
        Swift.print(message)
    }

    static func error(_ message: String) {
        let stderr = FileHandle.standardError
        let prefix = coloredOnStderr("[sshwitch error]", .red)
        stderr.write(Data(("\(prefix) \(message)\n").utf8))
    }

    static func info(_ message: String) {
        Swift.print("[sshwitch] \(message)")
    }

    static func success(_ message: String) {
        Swift.print("\(colored("✓", .green)) \(message)")
    }

    static func warn(_ message: String) {
        Swift.print("\(colored("!", .yellow)) \(message)")
    }

    static func hint(_ message: String) {
        Swift.print(colored("  \(message)", .yellow))
    }

    static func detail(_ message: String) {
        guard verboseEnabled else { return }
        Swift.print("  \(message)")
    }

    static func failure(_ message: String, cause: String? = nil, suggestion: String? = nil) {
        error(message)
        if let cause, !cause.isEmpty { error("Cause: \(cause)") }
        if let suggestion { error("Try: \(suggestion)") }
    }

    static func step(_ number: Int, of total: Int, _ message: String) {
        let indicator = colored("[\(number)/\(total)]", .bold)
        Swift.print("\(indicator) \(message)")
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
