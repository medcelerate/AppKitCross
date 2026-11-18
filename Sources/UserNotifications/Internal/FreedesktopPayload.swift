// UserNotifications (ADR-0043): the arguments of org.freedesktop.Notifications.Notify for a
// notification (Desktop Notifications Specification 1.2). Pure Swift so the macOS tests
// check it; FreedesktopNotifier marshals it onto the bus.
//
//   Notify(app_name s, replaces_id u, app_icon s, summary s, body s, actions as,
//          hints a{sv}, expire_timeout i) -> id u
//
// The title is the summary; the subtitle and body form the body (escaped when the server
// takes markup). Actions go in as (key, label) pairs with "default" for a click on the
// notification, when the server has the "actions" capability. A text-input action becomes the
// KDE "inline-reply" action when the server has that capability (its text arrives in the
// NotificationReplied signal), otherwise a plain button whose response carries empty text.
// A list-only notification (no banner) is sent with low urgency, which GNOME Shell and KDE
// Plasma put in the notification list without a banner.

import Foundation

struct FreedesktopPayload: Equatable {
    enum Hint: Equatable {
        case string(String)
        case bool(Bool)
        case byte(UInt8)
    }

    var appName: String
    var replacesID: UInt32
    var appIcon: String
    var summary: String
    var body: String
    var actions: [String]
    var hints: [(key: String, value: Hint)]
    var expireTimeout: Int32
    /// Maps the action keys sent to the server back to UNNotificationAction identifiers.
    var actionKeys: [String: String]

    static let defaultActionKey = "default"
    static let inlineReplyKey = "inline-reply"

    static func == (a: FreedesktopPayload, b: FreedesktopPayload) -> Bool {
        a.appName == b.appName && a.replacesID == b.replacesID && a.appIcon == b.appIcon && a.summary == b.summary && a.body == b.body
            && a.actions == b.actions && a.expireTimeout == b.expireTimeout && a.actionKeys == b.actionKeys
            && a.hints.map(\.key) == b.hints.map(\.key) && a.hints.map(\.value) == b.hints.map(\.value)
    }

    func hint(_ key: String) -> Hint? { hints.first { $0.key == key }?.value }

    static func make(for n: PlatformNotification, appName: String, desktopEntry: String, capabilities: Set<String>,
                     replacesID: UInt32 = 0, soundFile: (String) -> String? = FreedesktopPayload.bundledSound) -> FreedesktopPayload {
        let markup = capabilities.contains("body-markup")
        let summary = n.title.isEmpty ? n.subtitle : n.title
        var bodyLines: [String] = []
        if !n.title.isEmpty && !n.subtitle.isEmpty { bodyLines.append(n.subtitle) }
        if !n.body.isEmpty { bodyLines.append(n.body) }
        let body = bodyLines.map { markup ? escapeMarkup($0) : $0 }.joined(separator: "\n")

        var actions: [String] = []
        var keys: [String: String] = [:]
        if capabilities.contains("actions") {
            actions += [defaultActionKey, ""]
            keys[defaultActionKey] = UNNotificationDefaultActionIdentifier
            var usedInlineReply = false
            for action in n.actions {
                if action.textInput != nil, capabilities.contains("inline-reply"), !usedInlineReply {
                    usedInlineReply = true
                    actions += [inlineReplyKey, action.textInput!.buttonTitle.isEmpty ? action.title : action.textInput!.buttonTitle]
                    keys[inlineReplyKey] = action.identifier
                    continue
                }
                let key = action.identifier == defaultActionKey || action.identifier == inlineReplyKey ? "un-" + action.identifier : action.identifier
                actions += [key, action.title]
                keys[key] = action.identifier
            }
        }

        var hints: [(key: String, value: Hint)] = []
        if !desktopEntry.isEmpty { hints.append(("desktop-entry", .string(desktopEntry))) }
        let urgency: UInt8
        if n.listOnly {
            urgency = 0
        } else {
            switch n.interruptionLevel {
            case .passive: urgency = 0
            case .active: urgency = 1
            case .timeSensitive, .critical: urgency = 2
            }
        }
        hints.append(("urgency", .byte(urgency)))
        if n.playsSound {
            if let name = n.soundName, let path = soundFile(name) {
                hints.append(("sound-file", .string(path)))
            } else {
                hints.append(("sound-name", .string("message-new-instant")))
            }
        } else {
            hints.append(("suppress-sound", .bool(true)))
        }
        if let image = n.imageFiles.first { hints.append(("image-path", .string(image.path))) }
        if !n.threadIdentifier.isEmpty { hints.append(("x-appkitcross-thread", .string(n.threadIdentifier))) }

        return FreedesktopPayload(appName: appName, replacesID: replacesID, appIcon: "", summary: summary, body: body,
                                  actions: actions, hints: hints, expireTimeout: -1, actionKeys: keys)
    }

    /// A named sound: a file of that name in the main bundle's resources.
    static func bundledSound(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: nil)?.path
    }

    static func escapeMarkup(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
