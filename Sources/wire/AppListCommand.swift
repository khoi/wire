import ArgumentParser

struct AppListCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List running applications",
        aliases: ["ls"]
    )

    @Flag(help: "Include accessory apps")
    var includeAccessory = false

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = AppListService(client: context.apps)
        let data = try await service.list(includeAccessory: includeAccessory)
        return CommandExecution.success(
            data: data,
            plainText: data.plainText()
        )
    }
}
