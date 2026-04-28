import Foundation

@MainActor
@Observable
final class ToastState {
    static let shared = ToastState()

    var message: String?
    var position: ToastPosition?

    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, position: ToastPosition? = nil) {
        self.message = message
        self.position = position
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.message = nil
            self.position = nil
        }
    }
}
