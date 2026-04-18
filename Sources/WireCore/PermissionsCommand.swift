import ArgumentParser

struct PermissionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "permissions",
        subcommands: [
            PermissionsStatusCommand.self,
            PermissionsGrantCommand.self,
        ]
    )

    @OptionGroup var outputOptions: OutputOptions
}
