import ArgumentParser

struct ScrollCommand: ParsableCommand, WireExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll focused area or inspected element",
        discussion: """
        EXAMPLES:
          wire scroll --down 3
          wire scroll @e4 --up 5
          wire scroll 'text:"Reminders"' --down 2
        """
    )

    @Argument(help: "Element ref or query from inspect snapshot")
    var target: String?

    @Option(name: .customLong("up"), help: "Scroll up by wheel ticks")
    var up: Int?

    @Option(name: .customLong("down"), help: "Scroll down by wheel ticks")
    var down: Int?

    @OptionGroup var outputOptions: OutputOptions

    func execute(context: CommandContext) async throws -> CommandExecution {
        let service = ScrollService(
            permissions: context.permissions,
            client: context.scroll,
            logger: context.logger,
            currentDirectoryPath: context.currentDirectoryPath,
            stateDirectoryPath: context.stateDirectoryPath
        )
        let outcome = try await service.scroll(
            direction: try validatedDirection(),
            amount: try validatedAmount(),
            on: try validatedTarget()
        )
        return CommandExecution.success(
            data: outcome.data,
            plainText: outcome.data.plainText(snapshot: outcome.snapshot),
            snapshot: outcome.snapshot
        )
    }

    private func validatedTarget() throws -> SnapshotElementTarget? {
        guard let target else {
            return nil
        }
        return try SnapshotElementTarget.parse(
            target,
            emptyMessage: "scroll target cannot be empty",
            invalid: { ScrollError.invalidTarget($0) }
        )
    }

    private func validatedDirection() throws -> ScrollDirection {
        switch (up, down) {
        case (.some, .some):
            throw ScrollError.invalidAmount("provide exactly one of --up or --down")
        case (.some, nil):
            return .up
        case (nil, .some):
            return .down
        case (nil, nil):
            throw ScrollError.invalidAmount("provide exactly one of --up or --down")
        }
    }

    private func validatedAmount() throws -> Int {
        let amount: Int?
        switch (up, down) {
        case let (.some(up), nil):
            amount = up
        case let (nil, .some(down)):
            amount = down
        default:
            amount = nil
        }
        guard let amount else {
            throw ScrollError.invalidAmount("provide exactly one of --up or --down")
        }
        guard amount > 0 else {
            throw ScrollError.invalidAmount("scroll amount must be greater than zero")
        }
        return amount
    }
}
