import AppKit
import ApplicationServices

protocol SelectedTextSource {
    var isTrusted: Bool { get }
    var frontmostPID: pid_t? { get }
    func selectedText(in pid: pid_t) -> Result<String, SelectedTextReader.Failure>
}

/// Reads the actual selection through Accessibility. No synthetic key events,
/// clipboard snapshots, polling or clipboard writes, including failure paths.
final class SelectedTextReader {
    enum Failure: Error, Equatable {
        case permissionRequired
        case frontmostAppChanged
        case selectionUnavailable
        case noText
    }

    private let source: SelectedTextSource

    init(source: SelectedTextSource = AccessibilitySelectedTextSource()) {
        self.source = source
    }

    func capture(completion: @escaping (Result<String, Failure>) -> Void) {
        guard source.isTrusted else {
            completion(.failure(.permissionRequired))
            return
        }
        guard let pid = source.frontmostPID else {
            completion(.failure(.selectionUnavailable))
            return
        }
        let result = source.selectedText(in: pid)
        guard source.frontmostPID == pid else {
            completion(.failure(.frontmostAppChanged))
            return
        }
        if case .success(let text) = result, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(.failure(.noText))
        } else {
            completion(result)
        }
    }
}

struct AccessibilitySelectedTextSource: SelectedTextSource {
    var isTrusted: Bool { AccessibilityPermission.isTrusted() }
    var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    func selectedText(in pid: pid_t) -> Result<String, SelectedTextReader.Failure> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let focused = attribute(kAXFocusedUIElementAttribute, of: app),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .failure(.selectionUnavailable)
        }
        let element = focused as! AXUIElement
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else {
            return .failure(.frontmostAppChanged)
        }
        AXUIElementSetMessagingTimeout(element, 0.3)
        if attribute(kAXSubroleAttribute, of: element) as? String == kAXSecureTextFieldSubrole {
            return .failure(.selectionUnavailable)
        }
        if let text = attribute(kAXSelectedTextAttribute, of: element) as? String {
            return .success(text)
        }

        // Some text controls expose only a selected range. Never return the whole
        // AXValue when there is no selection, and never search unrelated controls.
        guard let rangeValue = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return .failure(.selectionUnavailable)
        }
        let axRange = rangeValue as! AXValue
        var range = CFRange()
        guard AXValueGetType(axRange) == .cfRange,
              AXValueGetValue(axRange, .cfRange, &range), range.location >= 0, range.length >= 0 else {
            return .failure(.selectionUnavailable)
        }
        guard range.length > 0 else { return .failure(.noText) }
        var selected: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                      rangeValue, &selected) == .success,
           let text = selected as? String {
            return .success(text)
        }
        guard let value = attribute(kAXValueAttribute, of: element) as? String,
              let text = Self.substring(value, range: range) else {
            return .failure(.selectionUnavailable)
        }
        return .success(text)
    }

    static func substring(_ text: String, range: CFRange) -> String? {
        let value = text as NSString
        guard range.location >= 0, range.length > 0, range.location <= value.length,
              range.length <= value.length - range.location else { return nil }
        let utf16 = text.utf16
        let lower = utf16.index(utf16.startIndex, offsetBy: range.location)
        let upper = utf16.index(lower, offsetBy: range.length)
        // Refuse ranges that split a Unicode character rather than invent text.
        guard let start = String.Index(lower, within: text),
              let end = String.Index(upper, within: text) else { return nil }
        return String(text[start..<end])
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
