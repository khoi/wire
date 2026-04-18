import ArgumentParser

struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        subcommands: [
            AppLaunchCommand.self,
        ]
    )

    @OptionGroup var outputOptions: OutputOptions
}
