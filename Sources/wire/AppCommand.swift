import ArgumentParser

struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        subcommands: [
            AppListCommand.self,
            AppLaunchCommand.self,
            AppQuitCommand.self,
        ]
    )

    @OptionGroup var outputOptions: OutputOptions
}
