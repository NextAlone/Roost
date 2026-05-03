import CoreGraphics
import Foundation
import RoostHostdCore

@MainActor
@Observable
final class HostdOwnedTerminalOutputModel {
    enum Status: Equatable {
        case waiting
        case streaming
        case failed(String)
    }

    private let bufferLimit: Int
    private let defaultTimeout: TimeInterval
    private let defaultIdleSleepNanoseconds: UInt64
    private let defaultErrorSleepNanoseconds: UInt64
    private var lastResizedGrid: HostdOwnedTerminalGrid?

    var text = ""
    var status: Status = .waiting

    init(
        bufferLimit: Int = 128 * 1024,
        timeout: TimeInterval = 0.25,
        idleSleepNanoseconds: UInt64 = 50_000_000,
        errorSleepNanoseconds: UInt64 = 500_000_000
    ) {
        self.bufferLimit = bufferLimit
        self.defaultTimeout = timeout
        self.defaultIdleSleepNanoseconds = idleSleepNanoseconds
        self.defaultErrorSleepNanoseconds = errorSleepNanoseconds
    }

    func stream(
        client: (any RoostHostdClient)?,
        paneID: UUID,
        timeout: TimeInterval? = nil,
        idleSleepNanoseconds: UInt64? = nil,
        errorSleepNanoseconds: UInt64? = nil
    ) async {
        guard let client else {
            status = .failed("Hostd client unavailable")
            return
        }

        let readTimeout = timeout ?? defaultTimeout
        let idleSleep = idleSleepNanoseconds ?? defaultIdleSleepNanoseconds
        let errorSleep = errorSleepNanoseconds ?? defaultErrorSleepNanoseconds
        status = text.isEmpty ? .waiting : .streaming

        while !Task.isCancelled {
            do {
                let data = try await client.readSessionOutput(id: paneID, timeout: readTimeout)
                if !data.isEmpty {
                    append(data)
                }
                if status != .streaming {
                    status = .streaming
                }
                if data.isEmpty {
                    try? await Task.sleep(nanoseconds: idleSleep)
                }
            } catch is CancellationError {
                return
            } catch {
                status = .failed(error.localizedDescription)
                try? await Task.sleep(nanoseconds: errorSleep)
            }
        }
    }

    func sendInput(client: (any RoostHostdClient)?, paneID: UUID, data: Data) async {
        guard !data.isEmpty else { return }
        guard let client else {
            status = .failed("Hostd client unavailable")
            return
        }

        do {
            try await client.writeSessionInput(id: paneID, data: data)
            if case .failed = status {
                status = text.isEmpty ? .waiting : .streaming
            }
        } catch is CancellationError {
            return
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func sendSignal(client: (any RoostHostdClient)?, paneID: UUID, signal: HostdSessionSignal) async {
        guard let client else {
            status = .failed("Hostd client unavailable")
            return
        }

        do {
            try await client.sendSessionSignal(id: paneID, signal: signal)
            if case .failed = status {
                status = text.isEmpty ? .waiting : .streaming
            }
        } catch is CancellationError {
            return
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func resize(
        client: (any RoostHostdClient)?,
        paneID: UUID,
        size: CGSize,
        cellSize: CGSize = HostdOwnedTerminalGridCalculator.defaultCellSize,
        horizontalPadding: CGFloat = HostdOwnedTerminalGridCalculator.defaultHorizontalPadding,
        verticalPadding: CGFloat = HostdOwnedTerminalGridCalculator.defaultVerticalPadding
    ) async {
        guard let grid = HostdOwnedTerminalGridCalculator.grid(
            for: size,
            cellSize: cellSize,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
        else { return }
        guard grid != lastResizedGrid else { return }
        guard let client else {
            status = .failed("Hostd client unavailable")
            return
        }

        do {
            try await client.resizeSession(id: paneID, columns: grid.columns, rows: grid.rows)
            lastResizedGrid = grid
            if case .failed = status {
                status = text.isEmpty ? .waiting : .streaming
            }
        } catch is CancellationError {
            return
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func append(_ data: Data) {
        let bytes = Array(data)
        text += String(bytes: bytes, encoding: .utf8) ?? "\u{FFFD}"
        guard text.count > bufferLimit else { return }
        text = String(text.suffix(bufferLimit))
    }
}
