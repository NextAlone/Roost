import Foundation
import MuxyShared

struct NotificationDeliverySettings: Equatable {
    let enabled: Bool
    let toastEnabled: Bool
    let sound: String
    let toastPosition: ToastPosition

    func applying(_ config: RoostConfigNotifications) -> NotificationDeliverySettings {
        NotificationDeliverySettings(
            enabled: config.enabled ?? enabled,
            toastEnabled: config.toastEnabled ?? toastEnabled,
            sound: config.sound.flatMap(Self.validSound) ?? sound,
            toastPosition: config.toastPosition.flatMap(Self.validToastPosition) ?? toastPosition
        )
    }

    private static func validSound(_ raw: String) -> String? {
        NotificationSound(rawValue: raw)?.rawValue
    }

    private static func validToastPosition(_ raw: String) -> ToastPosition? {
        ToastPosition(rawValue: raw)
    }
}
