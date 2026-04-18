import ArgumentParser

struct AppLaunchCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an application"
    )

    @Argument(help: "Application name or path")
    var app: String?

    @Option(name: .customLong("bundle-id"), help: "Launch by bundle identifier")
    var bundleID: String?

    @Option(
        name: .customLong("open"),
        parsing: .upToNextOption,
        help: "Document or URL to open immediately after launch"
    )
    var openTargets: [String] = []

    @Flag(help: "Wait until the application reports it finished launching")
    var wait = false

    @Flag(help: "Bring the application to the foreground after launch")
    var focus = false

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = AppLaunchService(
            client: context.apps,
            logger: context.logger,
            currentDirectoryPath: context.currentDirectoryPath
        )
        let data = try await service.launch(
            target: try validatedTarget(),
            openTargets: openTargets,
            wait: wait,
            focus: focus
        )
        return CommandExecution.success(
            data: data,
            plainText: data.plainText()
        )
    }

    private func validatedTarget() throws -> AppLaunchTarget {
        let app = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (app, bundleID) {
        case let (.some(app), nil) where !app.isEmpty:
            return .app(app)
        case let (nil, .some(bundleID)) where !bundleID.isEmpty:
            return .bundleID(bundleID)
        case (.some, .some):
            throw AppLaunchError.invalidTarget("provide either <app> or --bundle-id, not both")
        default:
            throw CleanExit.helpRequest(self)
        }
    }
}
