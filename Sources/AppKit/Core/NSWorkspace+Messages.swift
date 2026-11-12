// NSWorkspace's typed notification messages (macOS 26): each wraps one of the
// NSWorkspace notifications posted on `NSWorkspace.shared.notificationCenter`, carrying the
// userInfo values as properties. Hand-written (listed under skipMembers in
// tools/apigen/config.json); see ADR-0033.
//
// Foundation's `NotificationCenter.MainActorMessage` protocol is not in corelibs Foundation,
// so the structs do not declare the conformance; the members are the protocol's.

import Foundation

/// A URL from a userInfo value posted as `URL` or `NSURL`.
private func _workspaceMessageURL(_ value: Any?) -> URL? {
    if let url = value as? URL { return url }
    if let url = value as? NSURL { return url as URL }
    return nil
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didHideApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidHideApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.didHideApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidHideApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return DidHideApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidHideApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidHideApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didUnhideApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidUnhideApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.didUnhideApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidUnhideApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return DidUnhideApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidUnhideApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidUnhideApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.willLaunchApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct WillLaunchApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.willLaunchApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.WillLaunchApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return WillLaunchApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.WillLaunchApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.WillLaunchApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didLaunchApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidLaunchApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.didLaunchApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidLaunchApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return DidLaunchApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidLaunchApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidLaunchApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.willSleepNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct WillSleepMessage {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.willSleepNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.WillSleepMessage? {
            guard notification.name == name else { return nil }
            return WillSleepMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.WillSleepMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.WillSleepMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didWakeNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidWakeMessage {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.didWakeNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidWakeMessage? {
            guard notification.name == name else { return nil }
            return DidWakeMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidWakeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidWakeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didTerminateApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidTerminateApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.didTerminateApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidTerminateApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return DidTerminateApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidTerminateApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidTerminateApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didMountNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidMountVolumeMessage {
        public let localizedVolumeName: String
        public let volumeURL: URL
        public init(localizedVolumeName: String, volumeURL: URL) {
            self.localizedVolumeName = localizedVolumeName
            self.volumeURL = volumeURL
        }
        static public var name: Notification.Name { NSWorkspace.didMountNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidMountVolumeMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let localizedVolumeName = info[NSWorkspace.localizedVolumeNameUserInfoKey] as? String else { return nil }
            guard let volumeURL = _workspaceMessageURL(info[NSWorkspace.volumeURLUserInfoKey]) else { return nil }
            return DidMountVolumeMessage(localizedVolumeName: localizedVolumeName, volumeURL: volumeURL)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidMountVolumeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.localizedVolumeNameUserInfoKey: message.localizedVolumeName,
                NSWorkspace.volumeURLUserInfoKey: message.volumeURL
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidMountVolumeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.willUnmountNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct WillUnmountVolumeMessage {
        public let localizedVolumeName: String
        public let volumeURL: URL
        public init(localizedVolumeName: String, volumeURL: URL) {
            self.localizedVolumeName = localizedVolumeName
            self.volumeURL = volumeURL
        }
        static public var name: Notification.Name { NSWorkspace.willUnmountNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.WillUnmountVolumeMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let localizedVolumeName = info[NSWorkspace.localizedVolumeNameUserInfoKey] as? String else { return nil }
            guard let volumeURL = _workspaceMessageURL(info[NSWorkspace.volumeURLUserInfoKey]) else { return nil }
            return WillUnmountVolumeMessage(localizedVolumeName: localizedVolumeName, volumeURL: volumeURL)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.WillUnmountVolumeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.localizedVolumeNameUserInfoKey: message.localizedVolumeName,
                NSWorkspace.volumeURLUserInfoKey: message.volumeURL
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.WillUnmountVolumeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didUnmountNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidUnmountVolumeMessage {
        public let localizedVolumeName: String
        public let volumeURL: URL
        public init(localizedVolumeName: String, volumeURL: URL) {
            self.localizedVolumeName = localizedVolumeName
            self.volumeURL = volumeURL
        }
        static public var name: Notification.Name { NSWorkspace.didUnmountNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidUnmountVolumeMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let localizedVolumeName = info[NSWorkspace.localizedVolumeNameUserInfoKey] as? String else { return nil }
            guard let volumeURL = _workspaceMessageURL(info[NSWorkspace.volumeURLUserInfoKey]) else { return nil }
            return DidUnmountVolumeMessage(localizedVolumeName: localizedVolumeName, volumeURL: volumeURL)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidUnmountVolumeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.localizedVolumeNameUserInfoKey: message.localizedVolumeName,
                NSWorkspace.volumeURLUserInfoKey: message.volumeURL
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidUnmountVolumeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didActivateApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidActivateApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.didActivateApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidActivateApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return DidActivateApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidActivateApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidActivateApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didDeactivateApplicationNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidDeactivateApplicationMessage {
        public let application: NSRunningApplication
        public init(application: NSRunningApplication) {
            self.application = application
        }
        static public var name: Notification.Name { NSWorkspace.didDeactivateApplicationNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidDeactivateApplicationMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let application = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
            return DidDeactivateApplicationMessage(application: application)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidDeactivateApplicationMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.applicationUserInfoKey: message.application
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidDeactivateApplicationMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didRenameVolumeNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidRenameVolumeMessage {
        public let localizedVolumeName: String
        public let oldLocalizedVolumeName: String
        public let oldVolumeURL: URL
        public let volumeURL: URL
        public init(localizedVolumeName: String, volumeURL: URL, oldLocalizedVolumeName: String, oldVolumeURL: URL) {
            self.localizedVolumeName = localizedVolumeName
            self.oldLocalizedVolumeName = oldLocalizedVolumeName
            self.oldVolumeURL = oldVolumeURL
            self.volumeURL = volumeURL
        }
        static public var name: Notification.Name { NSWorkspace.didRenameVolumeNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidRenameVolumeMessage? {
            guard notification.name == name else { return nil }
            let info = notification.userInfo ?? [:]
            guard let localizedVolumeName = info[NSWorkspace.localizedVolumeNameUserInfoKey] as? String else { return nil }
            guard let oldLocalizedVolumeName = info[NSWorkspace.oldLocalizedVolumeNameUserInfoKey] as? String else { return nil }
            guard let oldVolumeURL = _workspaceMessageURL(info[NSWorkspace.oldVolumeURLUserInfoKey]) else { return nil }
            guard let volumeURL = _workspaceMessageURL(info[NSWorkspace.volumeURLUserInfoKey]) else { return nil }
            return DidRenameVolumeMessage(localizedVolumeName: localizedVolumeName, volumeURL: volumeURL, oldLocalizedVolumeName: oldLocalizedVolumeName, oldVolumeURL: oldVolumeURL)
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidRenameVolumeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared, userInfo: [
                NSWorkspace.localizedVolumeNameUserInfoKey: message.localizedVolumeName,
                NSWorkspace.oldLocalizedVolumeNameUserInfoKey: message.oldLocalizedVolumeName,
                NSWorkspace.oldVolumeURLUserInfoKey: message.oldVolumeURL,
                NSWorkspace.volumeURLUserInfoKey: message.volumeURL
            ])
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidRenameVolumeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.sessionDidBecomeActiveNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct SessionDidBecomeActiveMessage {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.sessionDidBecomeActiveNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.SessionDidBecomeActiveMessage? {
            guard notification.name == name else { return nil }
            return SessionDidBecomeActiveMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.SessionDidBecomeActiveMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.SessionDidBecomeActiveMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.sessionDidResignActiveNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct SessionDidResignActiveMessage {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.sessionDidResignActiveNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.SessionDidResignActiveMessage? {
            guard notification.name == name else { return nil }
            return SessionDidResignActiveMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.SessionDidResignActiveMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.SessionDidResignActiveMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.didChangeFileLabelsNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct DidChangeFileLabelsMessage {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.didChangeFileLabelsNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.DidChangeFileLabelsMessage? {
            guard notification.name == name else { return nil }
            return DidChangeFileLabelsMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.DidChangeFileLabelsMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.DidChangeFileLabelsMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.screensDidSleepNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct ScreensDidSleepMessage: Sendable {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.screensDidSleepNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.ScreensDidSleepMessage? {
            guard notification.name == name else { return nil }
            return ScreensDidSleepMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.ScreensDidSleepMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.ScreensDidSleepMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.screensDidWakeNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct ScreensDidWakeMessage: Sendable {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.screensDidWakeNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.ScreensDidWakeMessage? {
            guard notification.name == name else { return nil }
            return ScreensDidWakeMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.ScreensDidWakeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.ScreensDidWakeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.activeSpaceDidChangeNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct ActiveSpaceDidChangeMessage: Sendable {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.activeSpaceDidChangeNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.ActiveSpaceDidChangeMessage? {
            guard notification.name == name else { return nil }
            return ActiveSpaceDidChangeMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.ActiveSpaceDidChangeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.ActiveSpaceDidChangeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}

@available(macOS 26.0, *)
extension NSWorkspace {
    /// The `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` notification as a typed message.
    @available(macOS 26.0, *)
    public struct AccessibilityDisplayOptionsDidChangeMessage {
        public init() {}
        static public var name: Notification.Name { NSWorkspace.accessibilityDisplayOptionsDidChangeNotification }
        @MainActor public static func makeMessage(_ notification: Notification) -> NSWorkspace.AccessibilityDisplayOptionsDidChangeMessage? {
            guard notification.name == name else { return nil }
            return AccessibilityDisplayOptionsDidChangeMessage()
        }
        @MainActor public static func makeNotification(_ message: NSWorkspace.AccessibilityDisplayOptionsDidChangeMessage) -> Notification {
            Notification(name: name, object: NSWorkspace.shared)
        }
    }
}
@available(macOS 26.0, *)
extension NSWorkspace.AccessibilityDisplayOptionsDidChangeMessage {
    @available(macOS 26.0, *)
    public typealias Subject = NSWorkspace
}
