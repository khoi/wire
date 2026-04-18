import ArgumentParser

struct PermissionsGrantCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(commandName: "grant")

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) throws -> CommandExecution {
        let service = PermissionsService(client: context.permissions, logger: context.logger)
        do {
            let data = try service.grant()
            return try CommandExecution.success(
                command: "permissions grant",
                data: data,
                plainText: data.plainText(),
                exitCode: data.ready ? 0 : 1
            )
        } catch let error as PermissionsServiceError {
            throw WireFailure(
                command: "permissions grant",
                code: error.code,
                message: error.message,
                exitCode: 1
            )
        }
    }
}
