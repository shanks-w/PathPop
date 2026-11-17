import Carbon
import Foundation

protocol HotKeyBackend: AnyObject {
    var onPress: (() -> Void)? { get set }
    func register(_ shortcut: HotKeyShortcut) throws
    func unregister() throws
}

/// Main-thread owner of registration and preferences. Only commit after Carbon succeeds.
final class GlobalHotKey {
    private let backend: HotKeyBackend
    private let preferences: HotKeyPreferences
    private(set) var shortcut: HotKeyShortcut
    private(set) var isRegistered = false
    var onPress: (() -> Void)?

    init(preferences: HotKeyPreferences = UserDefaultsHotKeyPreferences(), backend: HotKeyBackend = CarbonHotKeyBackend()) {
        self.preferences = preferences
        self.backend = backend
        self.shortcut = preferences.load()
        backend.onPress = { [weak self] in
            guard let self, self.isRegistered else { return }
            self.onPress?()
        }
    }

    enum RegistrationError: Error {
        case installHandler(OSStatus)
        case register(OSStatus)
        case unregister(OSStatus)
        case invalidShortcut(HotKeyShortcut.ValidationError)
        case replacementFailed(attempted: HotKeyShortcut, previous: HotKeyShortcut, cause: String, rollbackFailure: String?)

        var detail: String {
            switch self {
            case .installHandler(let status): return "安装热键事件处理器失败（OSStatus \(status)）。"
            case .register(let status): return "注册全局快捷键失败（OSStatus \(status)），可能被系统或其他 App 占用。"
            case .unregister(let status): return "注销旧快捷键失败（OSStatus \(status)），已停止更改并保留原设置。"
            case .invalidShortcut(let error): return error.detail
            case .replacementFailed(let attempted, let previous, let cause, let rollbackFailure):
                let recovery = rollbackFailure.map {
                    "恢复原快捷键 \(previous.displayName) 也失败：\($0)\n当前全局快捷键不可用，原设置未覆盖。请重新录制或恢复默认；仍可从剪贴板定位路径。"
                } ?? "已恢复原快捷键 \(previous.displayName)，设置未更改。"
                return "无法使用 \(attempted.displayName)。\(cause)\n\n\(recovery)"
            }
        }
    }

    func register(_ requested: HotKeyShortcut? = nil) throws {
        let candidate = requested ?? shortcut
        if let error = candidate.validationError() { throw RegistrationError.invalidShortcut(error) }
        if isRegistered && candidate == shortcut { return }

        let previous = shortcut
        let wasRegistered = isRegistered
        // Never register the replacement until the old registration is released.
        if wasRegistered { try unregister() }
        do {
            try backend.register(candidate)
        } catch {
            guard wasRegistered else { throw error }
            var rollbackFailure: String?
            do {
                try backend.register(previous)
                isRegistered = true
            } catch {
                rollbackFailure = Self.detail(for: error)
            }
            throw RegistrationError.replacementFailed(
                attempted: candidate, previous: previous, cause: Self.detail(for: error), rollbackFailure: rollbackFailure
            )
        }
        shortcut = candidate
        isRegistered = true
        if requested != nil { preferences.save(candidate) }
    }

    func unregister() throws {
        try backend.unregister()
        isRegistered = false
    }

    static func detail(for error: Error) -> String {
        (error as? RegistrationError)?.detail ?? error.localizedDescription
    }
}

final class CarbonHotKeyBackend: HotKeyBackend {
    private static let signature: OSType = 0x5052564C // PRVL
    private static var nextIdentifier: UInt32 = 0
    private var identifier: UInt32 = 0
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPress: (() -> Void)?

    func register(_ shortcut: HotKeyShortcut) throws {
        precondition(hotKeyRef == nil, "Unregister before replacing a Carbon hotkey")
        if handlerRef == nil { try installHandler() }
        Self.nextIdentifier &+= 1
        let next = Self.nextIdentifier
        var registeredRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers.rawValue,
            EventHotKeyID(signature: Self.signature, id: next),
            // Exclusive registration makes an occupied combination fail instead
            // of accepting a silent, shadowed non-exclusive registration.
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &registeredRef
        )
        guard status == noErr else { throw GlobalHotKey.RegistrationError.register(status) }
        hotKeyRef = registeredRef
        identifier = next
    }

    private func installHandler() throws {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context -> OSStatus in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
                var eventID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID
                )
                guard status == noErr, eventID.signature == CarbonHotKeyBackend.signature,
                      eventID.id == backend.identifier, backend.hotKeyRef != nil else {
                    return OSStatus(eventNotHandledErr)
                }
                // Drop callbacks queued before a change/unregister. Leave Carbon before AppKit work.
                let pressedID = eventID.id
                DispatchQueue.main.async { [weak backend] in
                    guard let backend, backend.hotKeyRef != nil, backend.identifier == pressedID else { return }
                    backend.onPress?()
                }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard status == noErr else { throw GlobalHotKey.RegistrationError.installHandler(status) }
    }

    func unregister() throws {
        guard let hotKeyRef else { return }
        let status = UnregisterEventHotKey(hotKeyRef)
        guard status == noErr else { throw GlobalHotKey.RegistrationError.unregister(status) }
        self.hotKeyRef = nil
    }

    deinit {
        try? unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
