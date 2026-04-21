import ArgumentParser

struct PressCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "press",
        abstract: "Press a key or key combo",
        discussion: """
        EXAMPLES:
          wire press enter
          wire press cmd+l
          wire press cmd+shift+tab
        """
    )

    @Argument(help: "Key or key combo")
    var input: String?

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = PressService(
            permissions: context.permissions,
            client: context.press,
            logger: context.logger
        )
        let data = try await service.press(
            input: try validatedInput()
        )
        return CommandExecution.success(
            data: data,
            plainText: data.plainText()
        )
    }

    private func validatedInput() throws -> String {
        guard let input else {
            throw CleanExit.helpRequest(self)
        }
        return input
    }
}
