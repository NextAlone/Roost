import MuxyShared
import Testing

@testable import Roost

@Suite("NotificationDeliverySettings")
struct NotificationDeliverySettingsTests {
    @Test("config overrides notification delivery defaults")
    func overridesDefaults() {
        let defaults = NotificationDeliverySettings(
            enabled: true,
            toastEnabled: true,
            sound: NotificationSound.funk.rawValue,
            toastPosition: .topCenter
        )

        let settings = defaults.applying(RoostConfigNotifications(
            enabled: false,
            toastEnabled: false,
            sound: NotificationSound.ping.rawValue,
            toastPosition: ToastPosition.bottomRight.rawValue
        ))

        #expect(settings == NotificationDeliverySettings(
            enabled: false,
            toastEnabled: false,
            sound: NotificationSound.ping.rawValue,
            toastPosition: .bottomRight
        ))
    }

    @Test("invalid sound and position keep defaults")
    func invalidValuesKeepDefaults() {
        let defaults = NotificationDeliverySettings(
            enabled: true,
            toastEnabled: true,
            sound: NotificationSound.funk.rawValue,
            toastPosition: .topCenter
        )

        let settings = defaults.applying(RoostConfigNotifications(
            sound: "Unknown",
            toastPosition: "Somewhere"
        ))

        #expect(settings == defaults)
    }
}
