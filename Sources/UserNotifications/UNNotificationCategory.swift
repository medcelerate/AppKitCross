// UserNotifications (ADR-0043): categories and their actions. A category's actions become
// the buttons of the notification (Windows toast `<action>` elements, at most five; the
// freedesktop `actions` list, as many as the server shows); a text-input action becomes a
// toast text box on Windows and an inline reply where the Linux server supports one.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationactionicon
open class UNNotificationActionIcon: NSObject, @unchecked Sendable {
    let templateImageName: String?
    let systemImageName: String?

    init(templateImageName: String?, systemImageName: String?) {
        self.templateImageName = templateImageName
        self.systemImageName = systemImageName
        super.init()
    }

    public convenience init(templateImageName: String) { self.init(templateImageName: templateImageName, systemImageName: nil) }
    public convenience init(systemImageName: String) { self.init(templateImageName: nil, systemImageName: systemImageName) }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationaction
open class UNNotificationAction: NSObject, @unchecked Sendable {
    public let identifier: String
    public let title: String
    public let options: UNNotificationActionOptions
    public let icon: UNNotificationActionIcon?

    public init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: UNNotificationActionIcon?) {
        self.identifier = identifier
        self.title = title
        self.options = options
        self.icon = icon
        super.init()
    }

    public convenience init(identifier: String, title: String, options: UNNotificationActionOptions = []) {
        self.init(identifier: identifier, title: title, options: options, icon: nil)
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNNotificationAction, type(of: o) == type(of: self) else { return false }
        return o.identifier == identifier && o.title == title && o.options == options
    }

    open override var hash: Int { identifier.hashValue }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/untextinputnotificationaction
open class UNTextInputNotificationAction: UNNotificationAction, @unchecked Sendable {
    public let textInputButtonTitle: String
    public let textInputPlaceholder: String

    public init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: UNNotificationActionIcon?, textInputButtonTitle: String, textInputPlaceholder: String) {
        self.textInputButtonTitle = textInputButtonTitle
        self.textInputPlaceholder = textInputPlaceholder
        super.init(identifier: identifier, title: title, options: options, icon: icon)
    }

    public convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], textInputButtonTitle: String, textInputPlaceholder: String) {
        self.init(identifier: identifier, title: title, options: options, icon: nil, textInputButtonTitle: textInputButtonTitle, textInputPlaceholder: textInputPlaceholder)
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let o = object as? UNTextInputNotificationAction else { return false }
        return o.textInputButtonTitle == textInputButtonTitle && o.textInputPlaceholder == textInputPlaceholder
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationcategory
open class UNNotificationCategory: NSObject, @unchecked Sendable {
    public let identifier: String
    public let actions: [UNNotificationAction]
    public let intentIdentifiers: [String]
    public let options: UNNotificationCategoryOptions
    public let hiddenPreviewsBodyPlaceholder: String

    public init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], hiddenPreviewsBodyPlaceholder: String, options: UNNotificationCategoryOptions = []) {
        self.identifier = identifier
        self.actions = actions
        self.intentIdentifiers = intentIdentifiers
        self.hiddenPreviewsBodyPlaceholder = hiddenPreviewsBodyPlaceholder
        self.options = options
        super.init()
    }

    public convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) {
        self.init(identifier: identifier, actions: actions, intentIdentifiers: intentIdentifiers, hiddenPreviewsBodyPlaceholder: "", options: options)
    }

    // Set<UNNotificationCategory> is keyed by identifier, as Apple's is.
    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNNotificationCategory else { return false }
        return o.identifier == identifier && o.actions == actions && o.intentIdentifiers == intentIdentifiers && o.options == options
            && o.hiddenPreviewsBodyPlaceholder == hiddenPreviewsBodyPlaceholder
    }

    open override var hash: Int { identifier.hashValue }
}
