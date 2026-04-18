import Darwin

@main
enum Main {
    static func main() async {
        let code = await WireRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
