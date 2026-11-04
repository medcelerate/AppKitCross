// AVFoundation's error domain and the `AVError` codes the audio classes report.

import Foundation

public let AVFoundationErrorDomain = "AVFoundationErrorDomain"
public let AVErrorDeviceKey = "AVErrorDeviceKey"
public let AVErrorTimeKey = "AVErrorTimeKey"
public let AVErrorFileSizeKey = "AVErrorFileSizeKey"
public let AVErrorPIDKey = "AVErrorPIDKey"
public let AVErrorRecordingSuccessfullyFinishedKey = "AVErrorRecordingSuccessfullyFinishedKey"
public let AVErrorMediaTypeKey = "AVErrorMediaTypeKey"
public let AVErrorMediaSubTypeKey = "AVErrorMediaSubTypeKey"
public let AVErrorFileTypeKey = "AVErrorFileTypeKey"

/// - SeeAlso: https://developer.apple.com/documentation/avfoundation/averror
public struct AVError: CustomNSError, Hashable, Error {
    public enum Code: Int, Sendable {
        case unknown = -11800
        case outOfMemory = -11801
        case sessionNotRunning = -11803
        case deviceAlreadyUsedByAnotherSession = -11804
        case noDataCaptured = -11805
        case sessionConfigurationChanged = -11806
        case diskFull = -11807
        case deviceWasDisconnected = -11808
        case mediaChanged = -11809
        case maximumDurationReached = -11810
        case maximumFileSizeReached = -11811
        case mediaDiscontinuity = -11812
        case maximumNumberOfSamplesForFileFormatReached = -11813
        case deviceNotConnected = -11814
        case deviceInUseByAnotherApplication = -11815
        case deviceLockedForConfigurationByAnotherProcess = -11817
        case sessionWasInterrupted = -11818
        case mediaServicesWereReset = -11819
        case exportFailed = -11820
        case decodeFailed = -11821
        case invalidSourceMedia = -11822
        case fileAlreadyExists = -11823
        case compositionTrackSegmentsNotContiguous = -11824
        case invalidCompositionTrackSegmentDuration = -11825
        case invalidCompositionTrackSegmentSourceStartTime = -11826
        case invalidCompositionTrackSegmentSourceDuration = -11827
        case fileFormatNotRecognized = -11828
        case fileFailedToParse = -11829
        case maximumStillImageCaptureRequestsExceeded = -11830
        case contentIsProtected = -11831
        case noImageAtTime = -11832
        case decoderNotFound = -11833
        case encoderNotFound = -11834
        case contentIsNotAuthorized = -11835
        case applicationIsNotAuthorized = -11836
        case deviceIsNotAvailableInBackground = -11837
        case operationNotSupportedForAsset = -11838
        case decoderTemporarilyUnavailable = -11839
        case encoderTemporarilyUnavailable = -11840
        case invalidVideoComposition = -11841
        case referenceForbiddenByReferencePolicy = -11842
        case invalidOutputURLPathExtension = -11843
        case screenCaptureFailed = -11844
        case displayWasDisabled = -11845
        case torchLevelUnavailable = -11846
        case operationInterrupted = -11847
        case incompatibleAsset = -11848
        case failedToLoadMediaData = -11849
        case serverIncorrectlyConfigured = -11850
        case applicationIsNotAuthorizedToUseDevice = -11852
        case failedToParse = -11853
        case fileTypeDoesNotSupportSampleReferences = -11854
        case undecodableMediaData = -11855
        case airPlayControllerRequiresInternet = -11856
        case airPlayReceiverRequiresInternet = -11857
        case videoCompositorFailed = -11858
        case recordingAlreadyInProgress = -11859
        case unsupportedOutputSettings = -11861
        case operationNotAllowed = -11862
        case contentIsUnavailable = -11863
        case formatUnsupported = -11864
        case malformedDepth = -11865
        case contentNotUpdated = -11866
        case noLongerPlayable = -11867
        case noCompatibleAlternatesForExternalDisplay = -11868
        case noSourceTrack = -11869
        case externalPlaybackNotSupportedForAsset = -11870
        case operationNotSupportedForPreset = -11871
        case sessionHardwareCostOverage = -11872
        case unsupportedDeviceActiveFormat = -11873
        case incorrectlyConfigured = -11875
        case segmentStartedWithNonSyncSample = -11876
        case rosettaNotInstalled = -11877
        case operationCancelled = -11878
        case contentKeyRequestCancelled = -11879
        case sandboxExtensionDenied = -11881
        case toneMappingFailed = -11883
        case mediaExtensionDisabled = -11886
        case mediaExtensionConflict = -11887
        case encodeFailed = -11888
        case failedToLoadSampleData = -11889
    }
    public static var errorDomain: String { AVFoundationErrorDomain }
    public let code: Code
    public let userInfo: [String: Any]
    public init(_ code: Code, userInfo: [String: Any] = [:]) { self.code = code; self.userInfo = userInfo }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { userInfo }
    public var localizedDescription: String { (userInfo[NSLocalizedDescriptionKey] as? String) ?? "AVError \(code.rawValue)" }
    public static func == (a: AVError, b: AVError) -> Bool { a.code == b.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }
    public static var unknown: Code { .unknown }
    public static var fileFormatNotRecognized: Code { .fileFormatNotRecognized }
    public static var fileFailedToParse: Code { .fileFailedToParse }
    public static var failedToLoadMediaData: Code { .failedToLoadMediaData }
    public static var decodeFailed: Code { .decodeFailed }
}

extension AVError {
    /// The `NSError` form, which is what `AVAudioPlayer` and friends throw.
    func _nsError(_ description: String) -> NSError {
        var info = userInfo
        info[NSLocalizedDescriptionKey] = description
        return NSError(domain: AVFoundationErrorDomain, code: code.rawValue, userInfo: info)
    }
}
