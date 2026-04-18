import Darwin

let code = WireRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code)
