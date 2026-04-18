import ArgumentParser

struct InspectCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect an app, create snapshot, get elements ids",
        discussion: """
        EXAMPLES:
          wire inspect
          wire inspect --app "Google Chrome"
          wire inspect --plain
        """
    )

    @Option(help: "Application name to inspect")
    var app: String?

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = InspectService(
            permissions: context.permissions,
            client: context.inspect,
            logger: context.logger,
            currentDirectoryPath: context.currentDirectoryPath,
            stateDirectoryPath: context.stateDirectoryPath
        )
        let snapshot = try await service.inspect(target: try validatedTarget())
        return CommandExecution.success(
            data: snapshot.data,
            plainText: snapshot.plainText(),
            snapshot: snapshot.snapshot
        )
    }

    private func validatedTarget() throws -> InspectTarget {
        guard let app else {
            return .frontmost
        }
        let name = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw InspectError.invalidTarget("application name cannot be empty")
        }
        return .app(name)
    }
}
