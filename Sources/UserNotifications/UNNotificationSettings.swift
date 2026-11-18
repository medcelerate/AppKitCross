// UserNotifications (ADR-0043): the settings snapshot `getNotificationSettings` returns.
//
// Neither Windows nor Linux asks the user on the app's behalf, so the port keeps Apple's
// flow with the platform's own switch underneath: `notDetermined` until the app calls
// `requestAuthorization` (remembered in the app's defaults), then `authorized` while the
// platform lets the app notify and `denied` while it does not (Windows: Settings › System ›
// Notifications turned off for the app or for everything; Linux: no notification server on
// the session bus).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationsettings
open class UNNotificationSettings: NSObject, @unchecked Sendable {
    public let authorizationStatus: UNAuthorizationStatus
    public let soundSetting: UNNotificationSetting
    public let badgeSetting: UNNotificationSetting
    public let alertSetting: UNNotificationSetting
    public let notificationCenterSetting: UNNotificationSetting
    public let lockScreenSetting: UNNotificationSetting
    public let carPlaySetting: UNNotificationSetting
    public let alertStyle: UNAlertStyle
    public let showPreviewsSetting: UNShowPreviewsSetting
    public let criticalAlertSetting: UNNotificationSetting
    public let providesAppNotificationSettings: Bool
    public let timeSensitiveSetting: UNNotificationSetting
    public let scheduledDeliverySetting: UNNotificationSetting
    public let directMessagesSetting: UNNotificationSetting

    init(status: UNAuthorizationStatus, options: UNAuthorizationOptions, badgeSupported: Bool) {
        authorizationStatus = status
        let granted = status == .authorized || status == .provisional
        func setting(_ option: UNAuthorizationOptions) -> UNNotificationSetting {
            granted && options.contains(option) ? .enabled : .disabled
        }
        soundSetting = setting(.sound)
        badgeSetting = badgeSupported ? setting(.badge) : .notSupported
        alertSetting = status == .provisional ? .disabled : setting(.alert)
        notificationCenterSetting = granted ? .enabled : .disabled
        lockScreenSetting = .notSupported
        carPlaySetting = .notSupported
        alertStyle = granted && options.contains(.alert) && status != .provisional ? .banner : .none
        showPreviewsSetting = .always
        criticalAlertSetting = .notSupported
        providesAppNotificationSettings = options.contains(.providesAppNotificationSettings)
        timeSensitiveSetting = .notSupported
        scheduledDeliverySetting = .notSupported
        directMessagesSetting = .notSupported
        super.init()
    }
}
