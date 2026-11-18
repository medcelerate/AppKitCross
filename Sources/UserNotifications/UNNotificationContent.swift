// UserNotifications (ADR-0043): notification content, sounds and attachments.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationcontent
open class UNNotificationContent: NSObject, NSCopying, NSMutableCopying, @unchecked Sendable {
    // Storage shared with UNMutableNotificationContent, which makes each property settable.
    var _attachments: [UNNotificationAttachment] = []
    var _badge: NSNumber?
    var _body = ""
    var _categoryIdentifier = ""
    var _sound: UNNotificationSound?
    var _subtitle = ""
    var _threadIdentifier = ""
    var _title = ""
    var _userInfo: [AnyHashable: Any] = [:]
    var _targetContentIdentifier: String?
    var _interruptionLevel: UNNotificationInterruptionLevel = .active
    var _relevanceScore: Double = 0
    var _filterCriteria: String?

    public override init() { super.init() }

    open var attachments: [UNNotificationAttachment] { _attachments }
    open var badge: NSNumber? { _badge }
    open var body: String { _body }
    open var categoryIdentifier: String { _categoryIdentifier }
    open var sound: UNNotificationSound? { _sound }
    open var subtitle: String { _subtitle }
    open var threadIdentifier: String { _threadIdentifier }
    open var title: String { _title }
    open var userInfo: [AnyHashable: Any] { _userInfo }
    open var targetContentIdentifier: String? { _targetContentIdentifier }
    open var interruptionLevel: UNNotificationInterruptionLevel { _interruptionLevel }
    open var relevanceScore: Double { _relevanceScore }
    open var filterCriteria: String? { _filterCriteria }

    func copyStorage(to other: UNNotificationContent) {
        other._attachments = _attachments
        other._badge = _badge
        other._body = _body
        other._categoryIdentifier = _categoryIdentifier
        other._sound = _sound
        other._subtitle = _subtitle
        other._threadIdentifier = _threadIdentifier
        other._title = _title
        other._userInfo = _userInfo
        other._targetContentIdentifier = _targetContentIdentifier
        other._interruptionLevel = _interruptionLevel
        other._relevanceScore = _relevanceScore
        other._filterCriteria = _filterCriteria
    }

    /// An immutable copy, as Apple's returns even for mutable content.
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = UNNotificationContent()
        copyStorage(to: c)
        return c
    }

    open func mutableCopy(with zone: NSZone? = nil) -> Any {
        let c = UNMutableNotificationContent()
        copyStorage(to: c)
        return c
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNNotificationContent else { return false }
        return o._title == _title && o._subtitle == _subtitle && o._body == _body && o._badge == _badge
            && o._categoryIdentifier == _categoryIdentifier && o._threadIdentifier == _threadIdentifier
            && o._sound == _sound && o._attachments == _attachments
            && o._targetContentIdentifier == _targetContentIdentifier && o._interruptionLevel == _interruptionLevel
            && NSDictionary(dictionary: o._userInfo).isEqual(to: _userInfo)
    }

    open override var hash: Int { _title.hashValue ^ _body.hashValue }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent
open class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    public override init() { super.init() }

    open override var attachments: [UNNotificationAttachment] { get { _attachments } set { _attachments = newValue } }
    open override var badge: NSNumber? { get { _badge } set { _badge = newValue } }
    open override var body: String { get { _body } set { _body = newValue } }
    open override var categoryIdentifier: String { get { _categoryIdentifier } set { _categoryIdentifier = newValue } }
    open override var sound: UNNotificationSound? { get { _sound } set { _sound = newValue } }
    open override var subtitle: String { get { _subtitle } set { _subtitle = newValue } }
    open override var threadIdentifier: String { get { _threadIdentifier } set { _threadIdentifier = newValue } }
    open override var title: String { get { _title } set { _title = newValue } }
    open override var userInfo: [AnyHashable: Any] { get { _userInfo } set { _userInfo = newValue } }
    open override var targetContentIdentifier: String? { get { _targetContentIdentifier } set { _targetContentIdentifier = newValue } }
    open override var interruptionLevel: UNNotificationInterruptionLevel { get { _interruptionLevel } set { _interruptionLevel = newValue } }
    open override var relevanceScore: Double { get { _relevanceScore } set { _relevanceScore = newValue } }
    open override var filterCriteria: String? { get { _filterCriteria } set { _filterCriteria = newValue } }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationsoundname
public struct UNNotificationSoundName: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationsound
///
/// Windows plays the system notification sound for every sound (an unpackaged app's toast
/// cannot name its own audio file); Linux asks the notification server for the
/// `message-new-instant` theme sound, or plays a named sound file found in the main bundle.
open class UNNotificationSound: NSObject, @unchecked Sendable {
    /// nil for the default sound.
    let name: UNNotificationSoundName?

    init(name: UNNotificationSoundName?) {
        self.name = name
        super.init()
    }

    private static let _default = UNNotificationSound(name: nil)
    open class var `default`: UNNotificationSound { _default }

    public convenience init(named name: UNNotificationSoundName) {
        self.init(name: name)
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNNotificationSound else { return false }
        return o.name == name
    }

    open override var hash: Int { name?.hashValue ?? 0 }
}

/// Attachment option: a UTI string that overrides the type inferred from the file extension.
public let UNNotificationAttachmentOptionsTypeHintKey = "UNNotificationAttachmentOptionsTypeHintKey"
/// Attachment option: an NSNumber Bool that hides the thumbnail.
public let UNNotificationAttachmentOptionsThumbnailHiddenKey = "UNNotificationAttachmentOptionsThumbnailHiddenKey"
/// Attachment option: the normalized clipping rectangle of the thumbnail.
public let UNNotificationAttachmentOptionsThumbnailClippingRectKey = "UNNotificationAttachmentOptionsThumbnailClippingRectKey"
/// Attachment option: the frame or time of a movie to use as the thumbnail.
public let UNNotificationAttachmentOptionsThumbnailTimeKey = "UNNotificationAttachmentOptionsThumbnailTimeKey"

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationattachment
///
/// Apple copies the file into a data store; the port keeps the URL, so the file must stay in
/// place until the notification is shown. Images are shown on both platforms (an inline image
/// on a Windows toast, the `image-path` hint on Linux); audio and movie attachments are
/// accepted and carried but not shown.
open class UNNotificationAttachment: NSObject, @unchecked Sendable {
    public let identifier: String
    public let url: URL
    public let type: String

    init(identifier: String, url: URL, type: String) {
        self.identifier = identifier
        self.url = url
        self.type = type
        super.init()
    }

    public convenience init(identifier: String, url URL: URL, options: [AnyHashable: Any]? = nil) throws {
        guard URL.isFileURL else { throw UNError(.attachmentInvalidURL) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: URL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw UNError(.attachmentInvalidURL)
        }
        let hint = options?[UNNotificationAttachmentOptionsTypeHintKey] as? String
        guard let type = hint ?? UNNotificationAttachment.uti(forExtension: URL.pathExtension) else {
            throw UNError(.attachmentUnrecognizedType)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: URL.path)[.size] as? NSNumber)?.intValue ?? 0
        let limit = UNNotificationAttachment.isImage(type) ? 10_000_000 : UNNotificationAttachment.isAudio(type) ? 5_000_000 : 50_000_000
        guard size > 0, size <= limit else { throw UNError(.attachmentInvalidFileSize) }
        self.init(identifier: identifier.isEmpty ? UUID().uuidString : identifier, url: URL, type: type)
    }

    /// The types Apple's documentation lists for attachments.
    static func uti(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "public.png"
        case "jpg", "jpeg": return "public.jpeg"
        case "gif": return "com.compuserve.gif"
        case "aiff", "aif": return "public.aiff-audio"
        case "wav", "wave": return "com.microsoft.waveform-audio"
        case "mp3": return "public.mp3"
        case "m4a": return "com.apple.m4a-audio"
        case "mpg", "mpeg": return "public.mpeg"
        case "mp2": return "public.mpeg-2-video"
        case "mp4": return "public.mpeg-4"
        case "avi": return "public.avi"
        default: return nil
        }
    }

    static func isImage(_ type: String) -> Bool { ["public.png", "public.jpeg", "com.compuserve.gif"].contains(type) }
    static func isAudio(_ type: String) -> Bool { type.hasSuffix("-audio") || type == "public.mp3" }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNNotificationAttachment else { return false }
        return o.identifier == identifier && o.url == url && o.type == type
    }

    open override var hash: Int { identifier.hashValue }
}
