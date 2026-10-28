// Keysym tables shared by the X11 and Wayland backends (X keysyms and xkbcommon keysyms
// have the same values).

#if os(Linux)
import Foundation

enum LinuxKeys {
    /// Keysyms that AppKit reports as function-key characters or control characters,
    /// with the macOS virtual key code AppKit clients may compare against.
    static let special: [UInt: (String, UInt16)] = [
        0xff51: ("\u{F702}", 123), 0xff53: ("\u{F703}", 124), 0xff52: ("\u{F700}", 126), 0xff54: ("\u{F701}", 125),
        0xff50: ("\u{F729}", 115), 0xff57: ("\u{F72B}", 119), 0xff55: ("\u{F72C}", 116), 0xff56: ("\u{F72D}", 121),
        0xffff: ("\u{F728}", 117), 0xff08: ("\u{7F}", 51), 0xff0d: ("\r", 36), 0xff8d: ("\r", 76), 0xff09: ("\t", 48),
        0xff1b: ("\u{1B}", 53), 0xff63: ("\u{F727}", 114),
        0xffbe: ("\u{F704}", 122), 0xffbf: ("\u{F705}", 120), 0xffc0: ("\u{F706}", 99), 0xffc1: ("\u{F707}", 118),
        0xffc2: ("\u{F708}", 96), 0xffc3: ("\u{F709}", 97), 0xffc4: ("\u{F70A}", 98), 0xffc5: ("\u{F70B}", 100),
        0xffc6: ("\u{F70C}", 101), 0xffc7: ("\u{F70D}", 109), 0xffc8: ("\u{F70E}", 103), 0xffc9: ("\u{F70F}", 111),
    ]
    /// Shift, Control, Alt, Super and Caps Lock keysyms: reported as `flagsChanged`.
    static let modifiers: Set<UInt> = [0xffe1, 0xffe2, 0xffe3, 0xffe4, 0xffe9, 0xffea, 0xffeb, 0xffec, 0xffe5]
}
#endif
