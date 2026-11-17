// UserNotifications (ADR-0043): the Windows toast XML for a notification. Pure Swift so the
// macOS tests check it; WindowsToastNotifier hands it to the WinRT shim.
//
// Shape (ToastGeneric, Windows 10 and later):
//   <toast launch="{default action id}">
//     <visual><binding template="ToastGeneric">
//       <text>title</text><text>subtitle</text><text>body</text><image src="file:///…"/>
//     </binding></visual>
//     <actions>
//       <input id="text-N" type="text" placeHolderContent="…"/>            (text input actions)
//       <action content="Title" arguments="{action id}" activationType="foreground" [hint-inputId="text-N"]/>
//     </actions>
//     <audio src="ms-winsoundevent:Notification.Default"/> | <audio silent="true"/>
//   </toast>
// A click on the toast reports `launch`, a button its `arguments`, so the activation carries
// the UNNotificationAction identifier back unchanged. Every action uses foreground activation:
// an unpackaged app has no COM activator for background activation, and foreground
// activation of a running app only raises the Activated event (the center decides whether
// to bring the app forward).

import Foundation

enum ToastXML {
    /// Windows shows at most five buttons.
    static let maximumActions = 5

    static func document(for n: PlatformNotification) -> String {
        var xml = "<toast launch=\"\(escape(UNNotificationDefaultActionIdentifier))\">"
        xml += "<visual><binding template=\"ToastGeneric\">"
        // ToastGeneric shows up to three text lines: the first is the title.
        let lines = [n.title, n.subtitle, n.body].filter { !$0.isEmpty }
        for line in lines.prefix(3) { xml += "<text>\(escape(line))</text>" }
        if lines.isEmpty { xml += "<text></text>" }
        for image in n.imageFiles.prefix(1) { xml += "<image src=\"\(escape(image.absoluteString))\"/>" }
        xml += "</binding></visual>"
        let actions = n.actions.prefix(maximumActions)
        if !actions.isEmpty {
            xml += "<actions>"
            for (i, action) in actions.enumerated() {
                guard let text = action.textInput else { continue }
                xml += "<input id=\"text-\(i)\" type=\"text\" title=\"\(escape(action.title))\" placeHolderContent=\"\(escape(text.placeholder))\"/>"
            }
            for (i, action) in actions.enumerated() {
                let title = action.textInput?.buttonTitle ?? action.title
                xml += "<action content=\"\(escape(title))\" arguments=\"\(escape(action.identifier))\" activationType=\"foreground\""
                if action.textInput != nil { xml += " hint-inputId=\"text-\(i)\"" }
                xml += "/>"
            }
            xml += "</actions>"
        }
        if n.playsSound {
            xml += "<audio src=\"ms-winsoundevent:Notification.Default\"/>"
        } else {
            xml += "<audio silent=\"true\"/>"
        }
        xml += "</toast>"
        return xml
    }

    /// The input id a text action's text arrives under.
    static func inputIdentifier(forActionAt index: Int) -> String { "text-\(index)" }

    /// Toast tags are limited to 64 characters: longer identifiers are hashed (FNV-1a) into one.
    static func tag(for identifier: String) -> String {
        guard identifier.utf16.count > 64 else { return identifier }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in identifier.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return "un-" + String(hash, radix: 16)
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(c)
            }
        }
        return out
    }
}
