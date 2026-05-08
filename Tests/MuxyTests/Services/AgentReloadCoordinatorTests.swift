import Foundation
import Testing

@testable import Roost

@Suite("AgentReloadCoordinator")
struct AgentReloadCoordinatorTests {
    final class FakeClient: @unchecked Sendable {
        var interruptCalls = 0
        var killCalls = 0
        let exitAfterInterrupts: Int
        var exitedSignal = AsyncStream<Void>.makeStream()

        init(exitAfterInterrupts: Int) {
            self.exitAfterInterrupts = exitAfterInterrupts
        }

        func interrupt() async {
            interruptCalls += 1
            if interruptCalls >= exitAfterInterrupts {
                exitedSignal.continuation.yield()
                exitedSignal.continuation.finish()
            }
        }

        func kill() async {
            killCalls += 1
            exitedSignal.continuation.yield()
            exitedSignal.continuation.finish()
        }
    }

    @Test("exits after first interrupt")
    func exitsAfterFirstInterrupt() async {
        let fake = FakeClient(exitAfterInterrupts: 1)
        let coordinator = AgentReloadCoordinator(
            interruptStep: 50_000_000,
            forceKillStep: 50_000_000
        )
        await coordinator.driveExit(
            interrupt: { await fake.interrupt() },
            forceKill: { await fake.kill() },
            exitedStream: fake.exitedSignal.stream
        )
        #expect(fake.interruptCalls == 1)
        #expect(fake.killCalls == 0)
    }

    @Test("sends second interrupt then force kills")
    func sendsSecondInterruptThenForceKills() async {
        let fake = FakeClient(exitAfterInterrupts: 99)
        let coordinator = AgentReloadCoordinator(
            interruptStep: 50_000_000,
            forceKillStep: 50_000_000
        )
        await coordinator.driveExit(
            interrupt: { await fake.interrupt() },
            forceKill: { await fake.kill() },
            exitedStream: fake.exitedSignal.stream
        )
        #expect(fake.interruptCalls == 2)
        #expect(fake.killCalls == 1)
    }
}
