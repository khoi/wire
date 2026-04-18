import ArgumentParser

struct Wire: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wire",
        subcommands: [
            AppCommand.self,
            InspectCommand.self,
            PermissionsCommand.self,
        ]
    )

    @OptionGroup var outputOptions: OutputOptions
}
