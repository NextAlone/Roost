import Foundation

public actor AgentReloadCoordinator {
    public static let defaultInterruptStep: UInt64 = 3_000_000_000
    public static let defaultForceKillStep: UInt64 = 3_000_000_000

    private let interruptStep: UInt64
    private let forceKillStep: UInt64
    private var exitObserved = false

    public init(
        interruptStep: UInt64 = AgentReloadCoordinator.defaultInterruptStep,
        forceKillStep: UInt64 = AgentReloadCoordinator.defaultForceKillStep
    ) {
        self.interruptStep = interruptStep
        self.forceKillStep = forceKillStep
    }

    public func driveExit(
        interrupt: @Sendable () async -> Void,
        forceKill: @Sendable () async -> Void,
        exitedStream: AsyncStream<Void>
    ) async {
        exitObserved = false
        let consumer = Task { [weak self] in
            for await _ in exitedStream {
                await self?.markExitObserved()
                return
            }
        }
        defer { consumer.cancel() }

        await interrupt()
        if await waitForExit(nanoseconds: interruptStep) { return }
        await interrupt()
        if await waitForExit(nanoseconds: forceKillStep) { return }
        await forceKill()
        _ = await waitForExit(nanoseconds: forceKillStep)
    }

    private func markExitObserved() {
        exitObserved = true
    }

    private func waitForExit(nanoseconds: UInt64) async -> Bool {
        let pollInterval: UInt64 = 10_000_000
        var remaining = nanoseconds
        while remaining > 0 {
            if exitObserved { return true }
            let step = min(pollInterval, remaining)
            try? await Task.sleep(nanoseconds: step)
            remaining = remaining > step ? remaining - step : 0
        }
        return exitObserved
    }
}
