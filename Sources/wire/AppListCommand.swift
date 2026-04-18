import ArgumentParser

struct AppListCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List running applications",
        aliases: ["ls"]
    )

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = AppListService(client: context.apps)
        let data = try await service.list()
        return CommandExecution.success(
            data: data,
            plainText: data.plainText()
        )
    }
}
