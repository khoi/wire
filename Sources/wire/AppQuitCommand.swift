import ArgumentParser

struct AppQuitCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quit",
        abstract: "Quit running applications"
    )

    @Argument(help: "Application name")
    var app: String?

    @Option(name: .customLong("pid"), help: "Quit by process identifier")
    var pid: Int32?

    @Flag(help: "Force terminate the application")
    var force = false

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = AppQuitService(
            client: context.apps,
            logger: context.logger
        )
        let data = try await service.quit(
            target: try validatedTarget(),
            force: force
        )
        return CommandExecution.success(
            data: data,
            plainText: data.plainText(),
            exitCode: data.exitCode
        )
    }

    private func validatedTarget() throws -> AppQuitTarget {
        let app = app?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (app, pid) {
        case let (.some(app), nil) where !app.isEmpty:
            return .app(app)
        case let (nil, .some(pid)):
            return .pid(pid)
        case (.some, .some):
            throw AppQuitError.invalidTarget("provide either <app> or --pid, not both")
        default:
            throw CleanExit.helpRequest(self)
        }
    }
}
