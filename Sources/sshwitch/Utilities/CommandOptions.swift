import ArgumentParser

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Show files, commands, and configuration details.")
    var verbose = false

    func apply() {
        Output.configure(verbose: verbose)
    }
}
