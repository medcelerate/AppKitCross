// UserNotifications (ADR-0043): Apple's local-notification API on Windows and Linux.
// The option sets, enumerations and the error type, with Apple's raw values.
//
// On macOS the package does not build this module for apps (they get Apple's); the tests
// compile it there as `UserNotificationsPortable` against an in-memory backend.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unauthorizationoptions
public struct UNAuthorizationOptions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let carPlay = UNAuthorizationOptions(rawValue: 1 << 3)
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 1 << 4)
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 1 << 5)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unauthorizationstatus
public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationsetting
public enum UNNotificationSetting: Int, Sendable {
    case notSupported = 0
    case disabled = 1
    case enabled = 2
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unalertstyle
public enum UNAlertStyle: Int, Sendable {
    case none = 0
    case banner = 1
    case alert = 2
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unshowpreviewssetting
public enum UNShowPreviewsSetting: Int, Sendable {
    case always = 0
    case whenAuthenticated = 1
    case never = 2
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel
public enum UNNotificationInterruptionLevel: UInt, Sendable {
    case passive = 0
    case active = 1
    case timeSensitive = 2
    case critical = 3
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationpresentationoptions
public struct UNNotificationPresentationOptions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    @available(macOS, deprecated: 11.0, message: "Use list and banner")
    public static let alert = UNNotificationPresentationOptions(rawValue: 1 << 2)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 4)
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions
public struct UNNotificationActionOptions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let authenticationRequired = UNNotificationActionOptions(rawValue: 1 << 0)
    public static let destructive = UNNotificationActionOptions(rawValue: 1 << 1)
    public static let foreground = UNNotificationActionOptions(rawValue: 1 << 2)
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationcategoryoptions
public struct UNNotificationCategoryOptions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1 << 0)
    public static let allowInCarPlay = UNNotificationCategoryOptions(rawValue: 1 << 1)
    public static let hiddenPreviewsShowTitle = UNNotificationCategoryOptions(rawValue: 1 << 2)
    public static let hiddenPreviewsShowSubtitle = UNNotificationCategoryOptions(rawValue: 1 << 3)
}

/// The action identifier of a response to a click on the notification itself.
public let UNNotificationDefaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
/// The action identifier of a response to the user dismissing the notification (sent only
/// for categories with `.customDismissAction`).
public let UNNotificationDismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unerrordomain
public let UNErrorDomain = "UNErrorDomain"

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unerror
public struct UNError: CustomNSError, Hashable, Sendable {
    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unerror/code
    public enum Code: Int, Sendable, Hashable {
        case notificationsNotAllowed = 1
        case attachmentInvalidURL = 100
        case attachmentUnrecognizedType = 101
        case attachmentInvalidFileSize = 102
        case attachmentNotInDataStore = 103
        case attachmentMoveIntoDataStoreFailed = 104
        case attachmentCorrupt = 105
        case notificationInvalidNoDate = 1400
        case notificationInvalidNoContent = 1401
        case contentProvidingObjectNotAllowed = 1500
        case contentProvidingInvalid = 1501
        case badgeInputInvalid = 1600
    }

    public let code: Code
    private let description: String

    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.description = (userInfo[NSLocalizedDescriptionKey] as? String) ?? UNError.defaultDescription(code)
    }

    public static var errorDomain: String { UNErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: description] }

    public static var notificationsNotAllowed: Code { .notificationsNotAllowed }
    public static var attachmentInvalidURL: Code { .attachmentInvalidURL }
    public static var attachmentUnrecognizedType: Code { .attachmentUnrecognizedType }
    public static var attachmentInvalidFileSize: Code { .attachmentInvalidFileSize }
    public static var attachmentNotInDataStore: Code { .attachmentNotInDataStore }
    public static var attachmentMoveIntoDataStoreFailed: Code { .attachmentMoveIntoDataStoreFailed }
    public static var attachmentCorrupt: Code { .attachmentCorrupt }
    public static var notificationInvalidNoDate: Code { .notificationInvalidNoDate }
    public static var notificationInvalidNoContent: Code { .notificationInvalidNoContent }
    public static var contentProvidingObjectNotAllowed: Code { .contentProvidingObjectNotAllowed }
    public static var contentProvidingInvalid: Code { .contentProvidingInvalid }
    public static var badgeInputInvalid: Code { .badgeInputInvalid }

    private static func defaultDescription(_ code: Code) -> String {
        switch code {
        case .notificationsNotAllowed: return "Notifications are not allowed for this application"
        case .attachmentInvalidURL: return "Invalid attachment file URL"
        case .attachmentUnrecognizedType: return "Unrecognized attachment file type"
        case .attachmentInvalidFileSize: return "Invalid attachment file size"
        case .attachmentNotInDataStore: return "Attachment is not in the data store"
        case .attachmentMoveIntoDataStoreFailed: return "Could not move the attachment into the data store"
        case .attachmentCorrupt: return "Attachment is corrupt"
        case .notificationInvalidNoDate: return "Invalid notification: no date"
        case .notificationInvalidNoContent: return "Invalid notification: no content"
        case .contentProvidingObjectNotAllowed: return "Content providing object not allowed"
        case .contentProvidingInvalid: return "Content providing object is invalid"
        case .badgeInputInvalid: return "Invalid badge count"
        }
    }

    public static func == (lhs: UNError, rhs: UNError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }
}
