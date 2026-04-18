import ArgumentParser

struct Wire: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wire",
        subcommands: [
            PermissionsCommand.self,
        ]
    )

    @OptionGroup var outputOptions: OutputOptions
}
