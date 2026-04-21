import ArgumentParser

struct Wire: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wire",
        subcommands: [
            AppCommand.self,
            ClickCommand.self,
            InspectCommand.self,
            PressCommand.self,
            ScrollCommand.self,
            TypeCommand.self,
            PermissionsCommand.self,
        ]
    )

    @OptionGroup var outputOptions: OutputOptions
}
