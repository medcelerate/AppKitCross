// Pixel access for the host window's rendered image on every platform.
import Foundation
@testable import AppKit

func _pixels(_ image: CGImage) -> Data {
    #if os(Windows) || os(Linux)
    return image.data
    #else
    return image.dataProvider!.data! as Data
    #endif
}
