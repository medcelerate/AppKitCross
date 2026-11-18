// UserNotifications (ADR-0043): requests, delivered notifications and responses.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationrequest
open class UNNotificationRequest: NSObject, @unchecked Sendable {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?

    public convenience init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        // The request keeps an immutable copy, so later edits to mutable content do not reach it.
        self.init(identifier: identifier, copiedContent: content.copy() as! UNNotificationContent, trigger: trigger)
    }

    init(identifier: String, copiedContent: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = copiedContent
        self.trigger = trigger
        super.init()
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNNotificationRequest else { return false }
        return o.identifier == identifier && o.content.isEqual(content) && (o.trigger == nil ? trigger == nil : o.trigger!.isEqual(trigger))
    }

    open override var hash: Int { identifier.hashValue }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotification
open class UNNotification: NSObject, @unchecked Sendable {
    public let date: Date
    public let request: UNNotificationRequest

    init(date: Date, request: UNNotificationRequest) {
        self.date = date
        self.request = request
        super.init()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationresponse
open class UNNotificationResponse: NSObject, @unchecked Sendable {
    public let notification: UNNotification
    public let actionIdentifier: String

    init(notification: UNNotification, actionIdentifier: String) {
        self.notification = notification
        self.actionIdentifier = actionIdentifier
        super.init()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/untextinputnotificationresponse
open class UNTextInputNotificationResponse: UNNotificationResponse, @unchecked Sendable {
    public let userText: String

    init(notification: UNNotification, actionIdentifier: String, userText: String) {
        self.userText = userText
        super.init(notification: notification, actionIdentifier: actionIdentifier)
    }
}
