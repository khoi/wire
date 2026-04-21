import ArgumentParser

struct TypeCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into focused field or inspected element",
        discussion: """
        EXAMPLES:
          wire type "weather london"
          wire type "Today" --into @e4
          wire type "Today" --into 'text-field:"Title"'
        """
    )

    @Argument(help: "Text to type")
    var text: String?

    @Option(name: .customLong("into"), help: "Element ref or query from inspect snapshot")
    var into: String?

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = TypeService(
            permissions: context.permissions,
            client: context.type,
            logger: context.logger,
            currentDirectoryPath: context.currentDirectoryPath,
            stateDirectoryPath: context.stateDirectoryPath
        )
        let result = try await service.type(
            text: try validatedText(),
            into: try validatedTarget()
        )
        return CommandExecution.success(
            data: result.data,
            plainText: result.data.plainText(snapshot: result.snapshot),
            snapshot: result.snapshot
        )
    }

    private func validatedText() throws -> String {
        guard let text else {
            throw CleanExit.helpRequest(self)
        }
        return text
    }

    private func validatedTarget() throws -> SnapshotElementTarget? {
        guard let into else {
            return nil
        }
        return try SnapshotElementTarget.parse(
            into,
            emptyMessage: "type target cannot be empty",
            invalid: { TypeError.invalidTarget($0) }
        )
    }
}
