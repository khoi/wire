import ArgumentParser

struct PermissionsGrantCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(commandName: "grant")

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) throws -> CommandExecution {
        let service = PermissionsService(client: context.permissions, logger: context.logger)
        let data = try service.grant()
        return CommandExecution.success(
            data: data,
            plainText: data.plainText(),
            exitCode: data.ready ? 0 : 1
        )
    }
}
