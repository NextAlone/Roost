import Foundation
import MuxyShared

enum HostdRuntimePreferences {
    static func runtime(defaults: UserDefaults = .standard) -> RoostConfigHostdRuntime {
        guard let raw = defaults.string(forKey: GeneralSettingsKeys.hostdRuntime),
              let runtime = RoostConfigHostdRuntime(rawValue: raw)
        else {
            return .metadataOnly
        }
        return runtime
    }

    static func setRuntime(_ runtime: RoostConfigHostdRuntime, defaults: UserDefaults = .standard) {
        defaults.set(runtime.rawValue, forKey: GeneralSettingsKeys.hostdRuntime)
    }
}
