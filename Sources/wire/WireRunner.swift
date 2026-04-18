import ArgumentParser

enum WireRunner {
    @discardableResult
    static func run(
        arguments: [String],
        environment: WireEnvironment = .live()
    ) -> Int32 {
        do {
            let parsed = try Wire.parseAsRoot(arguments)

            if let executable = parsed as? any WireExecutableCommand {
                let outputOptions = executable.outputOptions
                let context = CommandContext(
                    environment: environment,
                    logger: Logger(isVerbose: outputOptions.verbose, write: environment.stderr)
                )
                do {
                    let execution = try executable.execute(context: context)
                    execution.write(options: outputOptions, environment: environment)
                    return execution.exitCode
                } catch let error as any WireError {
                    error.write(options: outputOptions, environment: environment)
                    return error.exitCode
                }
            }

            var command = parsed
            try command.run()
            return 0
        } catch let error as CleanExit {
            environment.stdout(Wire.message(for: error))
            return 0
        } catch let error as any WireError {
            error.writeJSON(environment: environment)
            return error.exitCode
        } catch {
            let failure = WireRuntimeError.parse(Wire.message(for: error))
            failure.writeJSON(environment: environment)
            return failure.exitCode
        }
    }
}
