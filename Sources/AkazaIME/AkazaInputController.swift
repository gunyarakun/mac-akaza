import Cocoa
import InputMethodKit

@objc(AkazaInputController)
class AkazaInputController: IMKInputController {
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown else {
            return false
        }

        guard let client = sender as? (any IMKTextInput) else {
            return false
        }

        let keyCode = event.keyCode
        let characters = event.characters ?? ""

        NSLog("AkazaIME: keyCode=\(keyCode) characters=\(characters)")

        // Return で確定
        if keyCode == 36 {
            return false
        }

        // Backspace
        if keyCode == 51 {
            return false
        }

        // 修飾キー付き（Cmd, Ctrl, Option）はスルー
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // 通常の文字入力
        if !characters.isEmpty {
            client.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0))
            return true
        }

        return false
    }
}
