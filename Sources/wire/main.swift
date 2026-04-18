import Darwin
import WireCore

@main
struct WireMain {
    static func main() {
        let code = WireRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
