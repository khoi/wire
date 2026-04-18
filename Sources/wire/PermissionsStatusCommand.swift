import ArgumentParser

struct PermissionsStatusCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(commandName: "status")

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) throws -> CommandExecution {
        let service = PermissionsService(client: context.permissions, logger: context.logger)
        let data = try service.status()
        return try CommandExecution.success(
            data: data,
            plainText: data.plainText()
        )
    }
}
