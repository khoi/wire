import ArgumentParser

public enum WireRunner {
    @discardableResult
    public static func run(
        arguments: [String],
        environment: WireEnvironment = .live()
    ) -> Int32 {
        let detectedOptions = OutputOptions.detect(arguments: arguments)

        do {
            let parsed = try Wire.parseAsRoot(arguments)

            if let executable = parsed as? any WireExecutableCommand {
                let outputOptions = executable.outputOptions
                let context = CommandContext(
                    environment: environment,
                    logger: Logger(isVerbose: outputOptions.verbose, write: environment.stderr)
                )
                let execution = try executable.execute(context: context)
                execution.write(options: outputOptions, environment: environment)
                return execution.exitCode
            }

            if parsed is PermissionsCommand {
                environment.stdout(PermissionsCommand.helpMessage())
                return 0
            }

            environment.stdout(Wire.helpMessage())
            return 0
        } catch let error as WireFailure {
            error.write(options: detectedOptions, environment: environment)
            return error.exitCode
        } catch let error as CleanExit {
            environment.stdout(Wire.message(for: error))
            return 0
        } catch {
            let failure = WireFailure(
                code: "parse_error",
                message: Wire.message(for: error),
                exitCode: 64
            )
            failure.write(options: detectedOptions, environment: environment)
            return failure.exitCode
        }
    }
}
