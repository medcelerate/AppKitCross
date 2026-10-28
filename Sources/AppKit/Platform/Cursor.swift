// Cursor seam.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum PlatformCursor: Sendable, Equatable {
    case arrow, iBeam, crosshair, pointingHand, openHand, closedHand, resizeLeftRight, resizeUpDown, resizeAll,
         operationNotAllowed, contextualMenu, dragCopy, dragLink, iBeamVertical, wait
    case custom(width: Int, height: Int, hotSpotX: Int, hotSpotY: Int, bgraPixels: [UInt8])
}
