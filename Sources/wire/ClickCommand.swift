import ArgumentParser

struct ClickCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an inspected UI element",
        discussion: """
        EXAMPLES:
          wire click @e3
          wire click "Continue"
          wire click 'button:"Continue"'
          wire click @e3 --snapshot s2
          wire click @e3 --right
        """
    )

    @Argument(help: "Element ref or query")
    var target: String?

    @Option(help: "Snapshot ID to use instead of the latest snapshot")
    var snapshot: String?

    @Flag(help: "Perform a physical right click")
    var right = false

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = ClickService(
            permissions: context.permissions,
            client: context.click,
            logger: context.logger,
            currentDirectoryPath: context.currentDirectoryPath,
            stateDirectoryPath: context.stateDirectoryPath
        )
        let data = try await service.click(
            target: try validatedTarget(),
            snapshotID: validatedSnapshotID(),
            right: right
        )
        return CommandExecution.success(
            data: data,
            plainText: data.plainText()
        )
    }

    private func validatedTarget() throws -> ClickTarget {
        guard let target else {
            throw CleanExit.helpRequest(self)
        }
        return try ClickTarget(parsing: target)
    }

    private func validatedSnapshotID() -> String? {
        let trimmed = snapshot?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
