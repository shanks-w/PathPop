import AppKit
import Carbon
import Foundation
import ApplicationServices

// Exercise the production UserDefaults adapter without writing any preferences
// outside this project, or changing the user's actual shortcut.
final class InMemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    var writes = 0
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
        writes += 1
    }
}

final class TestHotKeyBackend: HotKeyBackend {
    var onPress: (() -> Void)?
    var calls: [String] = []
    var registrationResults: [OSStatus] = []
    var unregisterFailure: OSStatus?
    var registered: HotKeyShortcut?

    func register(_ shortcut: HotKeyShortcut) throws {
        calls.append("register \(shortcut.displayName)")
        let status = registrationResults.isEmpty ? noErr : registrationResults.removeFirst()
        guard status == noErr else { throw GlobalHotKey.RegistrationError.register(status) }
        registered = shortcut
    }

    func unregister() throws {
        calls.append("unregister")
        if let unregisterFailure { throw GlobalHotKey.RegistrationError.unregister(unregisterFailure) }
        registered = nil
    }
}

final class TestSelectionSource: SelectedTextSource {
    var isTrusted = true
    var frontmostPID: pid_t? = 42
    var result: Result<String, SelectedTextReader.Failure> = .success("/tmp/selected.txt")
    var readCount = 0
    var onRead: (() -> Void)?
    func selectedText(in pid: pid_t) -> Result<String, SelectedTextReader.Failure> {
        readCount += 1
        onRead?()
        return result
    }
}

final class UITestApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in TestMain.runSuite() }
    }
}

@main
struct TestMain {
    static var passed = 0
    static var failed = 0
    static let home = "/Users/pathpop-test"

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
        }
    }

    static func expectPath(_ name: String, _ text: String, _ expected: String, alsoExisting: [String] = []) {
        let existing = Set([expected] + alsoExisting)
        let result = PathExtractor.extract(from: text, homeDirectory: home, fileExists: existing.contains)
        switch result {
        case .success(let url): check(name, url.path == expected && url.isFileURL)
        case .failure(let error):
            check(name, false)
            print("  Unexpected parser error: \(error)")
        }
    }

    static func expectConfirmation(_ name: String, _ text: String, _ expected: String, alsoExisting: [String] = []) {
        let existing = Set([expected] + alsoExisting)
        let result = PathExtractor.extract(from: text, homeDirectory: home, fileExists: existing.contains)
        if case .failure(.confirmationRequired(let paths)) = result {
            check(name, Set(paths) == existing && paths.count == existing.count)
        } else {
            check(name, false)
            print("  Expected explicit confirmation, got \(result)")
        }
    }

    static func parserTests() {
        let file = "/Users/pathpop-test/我的文档/项目 说明.txt"
        let source = "/Users/pathpop-test/Code/file.swift"
        expectPath("absolute path", source, source)
        expectPath("Chinese and spaces", file, file)
        expectPath("trim whitespace", " \n\t\(file)\n ", file)
        expectPath("home expansion", "~/我的文档/项目 说明.txt", file)
        expectPath("home folder", "~/", home)
        expectPath("directory", "/Users/pathpop-test/我的文档", "/Users/pathpop-test/我的文档")
        expectPath("file URL percent encoding", URL(fileURLWithPath: file).absoluteString, file)
        expectPath("localhost file URL", "file://localhost/Users/pathpop-test/我的文档/项目%20说明.txt", file)
        expectPath("file URL decoded once", "file:///tmp/a%2520b.txt", "/tmp/a%20b.txt")
        expectPath("encoded punctuation in URL", "file:///tmp/a%23b%3Fc.txt", "/tmp/a#b?c.txt")
        expectPath("double quotes", "\"\(file)\"", file)
        expectPath("single quotes", "'\(file)'", file)
        expectPath("backticks", "`\(file)`", file)
        expectPath("parentheses", "(\(file))", file)
        expectPath("square brackets", "[\(file)]", file)
        expectPath("braces", "{\(file)}", file)
        expectPath("angle brackets", "<\(file)>", file)
        expectPath("Chinese brackets", "【\(file)】", file)
        expectPath("Chinese quotes", "“\(file)”", file)
        expectPath("nested wrappers", "(`\(file)`)", file)
        expectConfirmation("line suffix", "\(source):12", source)
        expectConfirmation("line and column suffix", "\(source):12:3", source)
        expectConfirmation("quoted path then suffix", "\"\(source)\":12:3", source)
        expectConfirmation("suffix then quotes", "\"\(source):12:3\"", source)
        expectConfirmation("URL and suffix", URL(fileURLWithPath: source).absoluteString + ":12:3", source)
        expectPath("escaped space", file.replacingOccurrences(of: " ", with: "\\ "), file)
        expectPath("escaped home path", "~/我的文档/项目\\ 说明.txt", file)
        expectConfirmation("sentence with spaces", "请定位 \(file) 谢谢", file)
        expectConfirmation("Chinese prefix punctuation", "文件路径：\(file)，请查看。", file)
        expectConfirmation("quoted sentence", "找到文件：\"\(file)\"，然后继续", file)
        expectConfirmation("multiline selection", "编译失败\n\(source):12:3\n请检查", source)
        expectConfirmation("later existing candidate", "候选 /missing/no.txt 或 \(source)", source)
        expectConfirmation("longest space path first", "位置 /tmp/project notes.txt 附注", "/tmp/project notes.txt", alsoExisting: ["/tmp/project"])
        expectPath("whole text first", "/tmp/whole path", "/tmp/whole path", alsoExisting: ["/tmp/whole"])
        expectPath("literal colon filename first", source + ":12:3", source + ":12:3", alsoExisting: [source])
        expectPath("literal punctuation first", "/tmp/report.", "/tmp/report.", alsoExisting: ["/tmp/report"])
        expectPath("literal backslash first", "/tmp/a\\ b", "/tmp/a\\ b", alsoExisting: ["/tmp/a b"])
        expectPath("internal parentheses", "/tmp/report (final).txt", "/tmp/report (final).txt")
        expectPath("internal apostrophe", "/tmp/it's mine.txt", "/tmp/it's mine.txt")
        expectPath("emoji filename", "/tmp/🧭 路径.txt", "/tmp/🧭 路径.txt")
        expectConfirmation("sentence period", "查看 \(source).", source)
        expectPath("root directory", "/", "/")

        let empty = PathExtractor.extract(from: " \n\t ", homeDirectory: home, fileExists: { _ in true })
        check("empty selection failure", empty == .failure(.emptyText))
        for input in ["普通文字", "relative/file.swift", "https://example.com/file", "file://remote-server/share/file.txt", "file:///tmp/path?query=1", "file:///tmp/path#fragment"] {
            let result = PathExtractor.extract(from: input, homeDirectory: home, fileExists: { _ in true })
            check("reject nonlocal or unsupported: \(input)", result == .failure(.noPathFound))
        }
        let missing = PathExtractor.extract(from: "/missing/不存在 说明.txt", homeDirectory: home, fileExists: { _ in false })
        if case .failure(.pathsDoNotExist(let paths)) = missing {
            check("missing path included in error", paths.first == "/missing/不存在 说明.txt")
            check("missing candidates are unique", paths.count == Set(paths).count)
        } else { check("missing path produces error", false) }

        var attempted: [String] = []
        _ = PathExtractor.extract(from: "\(source):12:3", homeDirectory: home) {
            attempted.append($0)
            return $0 == source
        }
        check("literal before line suffix stripping", attempted == [source + ":12:3", source])
        for input in ["/tmp/report final.pdf", "\"/tmp/report final.pdf\"", "/tmp/report!", "/tmp/report.", "file:///tmp/report%20final.pdf"] {
            var checked: [String] = []
            let result = PathExtractor.extract(from: input, homeDirectory: home) {
                checked.append($0)
                return $0 == "/tmp/report"
            }
            check("missing exact path cannot become sibling: \(input)", {
                if case .failure(.pathsDoNotExist) = result { return !checked.contains("/tmp/report") }
                return false
            }())
        }
        expectConfirmation("numeric filename requires confirmation", "/tmp/report:2026", "/tmp/report")
        expectConfirmation("multiple paths never auto-select the longer one", "源 /tmp/a.txt 目标 /tmp/longer.txt", "/tmp/a.txt", alsoExisting: ["/tmp/longer.txt"])
        expectConfirmation("multiline paths require selection", "/tmp/a.txt\n/tmp/longer.txt", "/tmp/a.txt", alsoExisting: ["/tmp/longer.txt"])
        let cannotUseParent = PathExtractor.extract(from: "/existing/missing.txt", homeDirectory: home, fileExists: { $0 == "/existing" })
        check("does not silently fall back to parent directory", { if case .failure = cannotUseParent { return true }; return false }())
    }

    static func filesystemTests() throws {
        // Fixture files are created only under this project's build directory.
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/tests/fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("我的文档", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("项目 说明.txt")
        try Data("PathPop fixture".utf8).write(to: file)
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        let actual = PathExtractor.extract(from: "文件：`\(file.path):12:3`", homeDirectory: root.path, fileExists: exists)
        check("real filesystem embedded path needs confirmation", actual == .failure(.confirmationRequired([file.path])))
        let directory = PathExtractor.extract(from: "~/我的文档", homeDirectory: root.path, fileExists: exists)
        check("real filesystem folder and home", (try? directory.get().path) == folder.path)
        let url = PathExtractor.extract(from: file.absoluteString, homeDirectory: root.path, fileExists: exists)
        check("real filesystem file URL", (try? url.get().path) == file.path)
        let missing = PathExtractor.extract(from: folder.appendingPathComponent("missing.txt").path, homeDirectory: root.path, fileExists: exists)
        check("real filesystem nonexistent path", { if case .failure(.pathsDoNotExist) = missing { return true }; return false }())
    }

    static func selectionTests() throws {
        let source = TestSelectionSource()
        let reader = SelectedTextReader(source: source)
        func capture() -> Result<String, SelectedTextReader.Failure>? {
            var result: Result<String, SelectedTextReader.Failure>?
            reader.capture { result = $0 }
            return result
        }
        source.isTrusted = false
        check("selection denies access before reading without permission", capture() == .failure(.permissionRequired) && source.readCount == 0)
        source.isTrusted = true
        source.frontmostPID = nil
        check("selection needs a foreground application", capture() == .failure(.selectionUnavailable) && source.readCount == 0)
        source.frontmostPID = 42
        check("reads only the selected text", capture() == .success("/tmp/selected.txt"))
        source.result = .success(" \n\t")
        check("empty selection is not entire field or clipboard", capture() == .failure(.noText))
        source.result = .failure(.selectionUnavailable)
        check("unsupported controls require explicit manual copy", capture() == .failure(.selectionUnavailable))
        source.result = .success("/tmp/selected.txt")
        source.onRead = { source.frontmostPID = 99 }
        check("foreground switch discards stale selection", capture() == .failure(.frontmostAppChanged))
        check("UTF16 selection preserves emoji and Chinese", AccessibilitySelectedTextSource.substring("a🧭中文z", range: CFRange(location: 1, length: 4)) == "🧭中文")
        for range in [CFRange(location: -1, length: 1), CFRange(location: 0, length: 0), CFRange(location: 100, length: 1), CFRange(location: 1, length: Int.max), CFRange(location: 1, length: 1)] {
            check("invalid or split Unicode range is rejected: \(range)", AccessibilitySelectedTextSource.substring("a🧭z", range: range) == nil)
        }
    }

    static func selectionClipboardTests() throws {
        // Isolated board only. Simulate a concurrent user copy while the real
        // capture coordinator reads selection; no global clipboard or key events.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let source = TestSelectionSource()
        let reader = SelectedTextReader(source: source)
        for outcome: Result<String, SelectedTextReader.Failure> in [.success("/tmp/selected.txt"), .failure(.selectionUnavailable), .success("")] {
            board.clearContents()
            board.setString("ORIGINAL", forType: .string)
            var newestCount = 0
            source.onRead = {
                board.clearContents()
                board.setString("UNRELATED_NEW_USER_COPY", forType: .string)
                newestCount = board.changeCount
            }
            source.result = outcome
            var captured: Result<String, SelectedTextReader.Failure>?
            reader.capture { captured = $0 }
            check("capture never restores over newer clipboard writes", board.string(forType: .string) == "UNRELATED_NEW_USER_COPY" && board.changeCount == newestCount)
            check("capture never treats unrelated clipboard text as selection", captured != .success("UNRELATED_NEW_USER_COPY"))
        }
    }

    static func shortcutValueTests() throws {
        let r = UInt32(kVK_ANSI_R)
        check("default shortcut unchanged", HotKeyShortcut.default.displayName == "⌃⌥⌘R")
        check("default Carbon codes unchanged", HotKeyShortcut.default.keyCode == r && HotKeyShortcut.default.modifiers.rawValue == UInt32(controlKey | optionKey | cmdKey))
        check("default is valid", HotKeyShortcut.default.validationError() == nil)
        for (modifier, symbol) in [(HotKeyModifiers.command, "⌘"), (.option, "⌥"), (.control, "⌃"), (.shift, "⇧")] {
            let shortcut = HotKeyShortcut(keyCode: r, modifiers: modifier)
            check("single modifier policy: \(symbol)", shortcut.validationError() == (modifier == .shift ? .shiftOnly : nil))
            check("format one modifier: \(symbol)", shortcut.displayName == symbol + "R")
        }
        check("canonical modifier order", HotKeyShortcut(keyCode: r, modifiers: .supported).displayName == "⌃⌥⇧⌘R")
        for (code, name) in [(kVK_ANSI_1, "1"), (kVK_ANSI_Equal, "="), (kVK_Space, "Space"), (kVK_Tab, "Tab"), (kVK_Return, "Return"), (kVK_Delete, "Delete"), (kVK_ForwardDelete, "Forward Delete"), (kVK_F1, "F1"), (kVK_F20, "F20"), (kVK_LeftArrow, "←"), (kVK_ANSI_KeypadEnter, "Keypad Enter")] {
            let shortcut = HotKeyShortcut(keyCode: UInt32(code), modifiers: .option)
            check("format supported key: \(name)", shortcut.displayName == "⌥" + name && shortcut.validationError() == nil)
        }
        check("bare key rejected", HotKeyShortcut(keyCode: r, modifiers: []).validationError() == .missingModifier)
        for code: UInt32 in 54...63 {
            check("modifier alone rejected: \(code)", HotKeyShortcut(keyCode: code, modifiers: .command).validationError() == .modifierOnly)
            check("modifier only keeps recording: \(code)", HotKeyShortcut.recordingResult(keyCode: code, modifiers: .command) == .ignored)
        }
        check("unknown key rejected", HotKeyShortcut(keyCode: 999, modifiers: .command).validationError() == .unsupportedKey)
        check("unknown modifier rejected", HotKeyShortcut(keyCode: r, modifiers: [.command, HotKeyModifiers(rawValue: UInt32(alphaLock))]).validationError() == .unsupportedModifiers)
        check("Esc cannot be saved", HotKeyShortcut(keyCode: UInt32(kVK_Escape), modifiers: .command).validationError() == .escapeReserved)
        check("Esc cancels", HotKeyShortcut.recordingResult(keyCode: UInt32(kVK_Escape), modifiers: []) == .cancelled)
        check("modified Esc cancels", HotKeyShortcut.recordingResult(keyCode: UInt32(kVK_Escape), modifiers: .supported) == .cancelled)
        check("bare key gives recording feedback", HotKeyShortcut.recordingResult(keyCode: r, modifiers: []) == .invalid(.missingModifier))
        check("valid recording yields shortcut", HotKeyShortcut.recordingResult(keyCode: r, modifiers: .command) == .shortcut(HotKeyShortcut(keyCode: r, modifiers: .command)))
        check("AppKit maps all modifiers", HotKeyModifiers(eventFlags: [.control, .option, .shift, .command]) == .supported)
        check("Caps Lock and Fn do not count as modifiers", HotKeyModifiers(eventFlags: [.capsLock, .function, .numericPad]).isEmpty)
        check("extra event flags do not alter shortcut", HotKeyModifiers(eventFlags: [.command, .capsLock, .function, .numericPad]) == .command)

        for shortcut in [HotKeyShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: .command),
                         HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: .command),
                         HotKeyShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: .command),
                         HotKeyShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: [.command, .shift]),
                         HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .option, .shift])] {
            check("common shortcut is reserved: \(shortcut.displayName)", shortcut.validationError() == .reservedShortcut)
            check("reserved recording stays invalid", HotKeyShortcut.recordingResult(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) == .invalid(.reservedShortcut))
            let saved = try JSONEncoder().encode(shortcut)
            check("old unsafe preference migrates to default", HotKeyShortcut.decodePreference(saved) == .default)
        }
        let shiftA = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: .shift)
        check("Shift A cannot intercept typing", shiftA.validationError() == .shiftOnly)
        let savedShift = try JSONEncoder().encode(shiftA)
        check("old Shift-only preference defaults safely", HotKeyShortcut.decodePreference(savedShift) == .default)
        let custom = HotKeyShortcut(keyCode: UInt32(kVK_F6), modifiers: [.option, .shift])
        let encoded = try JSONEncoder().encode(custom)
        check("preference roundtrip", HotKeyShortcut.decodePreference(encoded) == custom)
        check("absent preference uses default", HotKeyShortcut.decodePreference(nil) == .default)
        for data in [Data("garbage".utf8), Data("{}".utf8), Data(#"{"keyCode":-1,"modifiers":256}"#.utf8), try JSONEncoder().encode(HotKeyShortcut(keyCode: r, modifiers: [])), try JSONEncoder().encode(HotKeyShortcut(keyCode: 999, modifiers: .command)), try JSONEncoder().encode(HotKeyShortcut(keyCode: UInt32(kVK_Escape), modifiers: .command))] {
            check("invalid saved preference safely defaults", HotKeyShortcut.decodePreference(data) == .default)
        }
    }

    static func shortcutTransactionTests() throws {
        let defaults = InMemoryDefaults()
        let preferences = UserDefaultsHotKeyPreferences(defaults: defaults)
        let backend = TestHotKeyBackend()
        let hotKey = GlobalHotKey(preferences: preferences, backend: backend)
        let custom = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: .option)
        let another = HotKeyShortcut(keyCode: UInt32(kVK_F6), modifiers: .command)
        check("initial preference defaults", hotKey.shortcut == .default && !hotKey.isRegistered)
        try hotKey.register()
        check("startup registers default without rewriting preferences", hotKey.isRegistered && backend.registered == .default && defaults.writes == 0)
        backend.calls = []
        try hotKey.register(custom)
        check("unregister precedes replacement", backend.calls == ["unregister", "register ⌥R"])
        check("success commits active shortcut and UserDefaults", hotKey.shortcut == custom && hotKey.isRegistered && preferences.load() == custom && defaults.writes == 1)
        backend.calls = []
        try hotKey.register(custom)
        check("same shortcut is a no-op", backend.calls.isEmpty && defaults.writes == 1)
        do {
            try hotKey.register(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: []))
            check("invalid replacement throws", false)
        } catch GlobalHotKey.RegistrationError.invalidShortcut {
            check("invalid replacement leaves registration and storage untouched", backend.calls.isEmpty && defaults.writes == 1 && hotKey.shortcut == custom)
        }

        backend.registrationResults = [OSStatus(eventHotKeyExistsErr), noErr]
        do {
            try hotKey.register(another)
            check("conflicting replacement throws", false)
        } catch let error as GlobalHotKey.RegistrationError {
            check("failure unregisters, attempts, then restores", backend.calls == ["unregister", "register ⌘F6", "register ⌥R"])
            check("failure retains previous active shortcut and persisted value", hotKey.isRegistered && hotKey.shortcut == custom && backend.registered == custom && preferences.load() == custom && defaults.writes == 1)
            check("failure explains conflict and successful rollback", error.detail.contains("已恢复原快捷键 ⌥R") && error.detail.contains("OSStatus") && error.detail.contains("系统或其他 App"))
        }
        var presses = 0
        hotKey.onPress = { presses += 1 }
        backend.onPress?()
        check("restored shortcut still invokes action", presses == 1)

        backend.calls = []
        backend.unregisterFailure = -50
        do {
            try hotKey.register(another)
            check("unregister failure throws", false)
        } catch GlobalHotKey.RegistrationError.unregister {
            check("failed unregister prevents replacement", backend.calls == ["unregister"] && hotKey.isRegistered && backend.registered == custom && defaults.writes == 1)
        }
        backend.unregisterFailure = nil

        backend.registrationResults = [OSStatus(eventHotKeyExistsErr), OSStatus(eventHotKeyExistsErr)]
        do {
            try hotKey.register(another)
            check("rollback failure throws", false)
        } catch let error as GlobalHotKey.RegistrationError {
            check("rollback failure explicitly reports unavailable state", !hotKey.isRegistered && error.detail.contains("当前全局快捷键不可用") && error.detail.contains("恢复原快捷键 ⌥R 也失败"))
            check("rollback failure preserves last saved configuration", hotKey.shortcut == custom && preferences.load() == custom && defaults.writes == 1)
        }
        backend.onPress?()
        check("unregistered hotkey cannot invoke action", presses == 1)
        try hotKey.register(custom)
        check("retry same configuration recovers after rollback failure", hotKey.isRegistered && backend.registered == custom)

        let restartedBackend = TestHotKeyBackend()
        let restarted = GlobalHotKey(preferences: UserDefaultsHotKeyPreferences(defaults: defaults), backend: restartedBackend)
        try restarted.register()
        check("restart loads and registers saved shortcut", restarted.shortcut == custom && restartedBackend.registered == custom)

        let writesBeforeRestore = defaults.writes
        backend.registrationResults = [OSStatus(eventHotKeyExistsErr), noErr]
        do {
            try hotKey.register(.default)
            check("restore-default conflict throws", false)
        } catch {
            check("restore-default conflict rolls back without saving", hotKey.isRegistered && hotKey.shortcut == custom && preferences.load() == custom && defaults.writes == writesBeforeRestore)
        }
        try hotKey.register(.default)
        check("restore default registers and persists default", hotKey.isRegistered && hotKey.shortcut == .default && preferences.load() == .default)

        let failingBackend = TestHotKeyBackend()
        failingBackend.registrationResults = [OSStatus(eventHotKeyExistsErr)]
        let startup = GlobalHotKey(preferences: preferences, backend: failingBackend)
        do {
            try startup.register()
            check("startup conflict throws", false)
        } catch {
            check("startup failure stays explicitly inactive", !startup.isRegistered && startup.shortcut == .default)
        }
        try startup.register(custom)
        check("settings recover from startup conflict", startup.isRegistered && preferences.load() == custom)

        backend.calls = []
        let writesBeforeReserved = defaults.writes
        for shortcut in [HotKeyShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: .command), HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: .shift)] {
            do {
                try hotKey.register(shortcut)
                check("unsafe shortcut registration rejected", false)
            } catch GlobalHotKey.RegistrationError.invalidShortcut {
                check("unsafe registration leaves old key and preferences intact", backend.calls.isEmpty && hotKey.isRegistered && defaults.writes == writesBeforeReserved)
            }
        }
        try hotKey.unregister()
        try restarted.unregister()
        try startup.unregister()
    }

    static func hotKeyTests() throws {
        _ = NSApplication.shared
        let firstPreferences = UserDefaultsHotKeyPreferences(defaults: InMemoryDefaults())
        let first = GlobalHotKey(preferences: firstPreferences)
        let second = GlobalHotKey(preferences: UserDefaultsHotKeyPreferences(defaults: InMemoryDefaults()))
        let probe = GlobalHotKey(preferences: UserDefaultsHotKeyPreferences(defaults: InMemoryDefaults()))
        try first.register()
        defer { try? first.unregister(); try? second.unregister(); try? probe.unregister() }
        check("Carbon hotkey registers", true)
        do {
            try second.register()
            check("Carbon duplicate hotkey reports failure", false)
        } catch GlobalHotKey.RegistrationError.register(let status) {
            check("Carbon duplicate hotkey reports failure", status != noErr)
        }
        let custom = HotKeyShortcut(keyCode: UInt32(kVK_F19), modifiers: .supported)
        try second.register(custom)
        do {
            try first.register(custom)
            check("Carbon conflicting replacement fails", false)
        } catch GlobalHotKey.RegistrationError.replacementFailed(_, _, _, let rollbackFailure) {
            check("Carbon conflicting replacement restores default", rollbackFailure == nil && first.isRegistered && first.shortcut == .default)
        }
        do {
            try probe.register()
            check("Carbon rollback actually reacquires old shortcut", false)
        } catch GlobalHotKey.RegistrationError.register {
            check("Carbon rollback actually reacquires old shortcut", true)
        }
        try second.unregister()
        try first.register(custom)
        check("Carbon replacement succeeds after conflict released", first.isRegistered && first.shortcut == custom)
        try probe.register()
        check("Carbon replacement releases previous shortcut", probe.isRegistered)
        try probe.unregister()
        try first.unregister()
        let restarted = GlobalHotKey(preferences: firstPreferences)
        defer { try? restarted.unregister() }
        try restarted.register()
        check("Carbon restart registers saved shortcut", restarted.shortcut == custom && restarted.isRegistered)
        try restarted.register(.default)
        check("Carbon restore default succeeds", restarted.shortcut == .default && restarted.isRegistered)
    }

    static func settingsWindowTests() throws {
        // AppKit-only smoke test: no CGEvent posting, Carbon registration,
        // user clipboard or on-disk UserDefaults writes.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if !app.isRunning { app.finishLaunching() }
        let defaults = InMemoryDefaults()
        let backend = TestHotKeyBackend()
        let hotKey = GlobalHotKey(preferences: UserDefaultsHotKeyPreferences(defaults: defaults), backend: backend)
        try hotKey.register()
        var changes = 0
        let controller = ShortcutSettingsWindowController(hotKey: hotKey) { changes += 1 }
        controller.present()
        defer { controller.close(); try? hotKey.unregister() }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        settle()
        guard let window = controller.window, let content = window.contentView else {
            throw NSError(domain: "PathPopUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "需要可访问的 macOS 桌面窗口服务。"])
        }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func button(_ title: String) -> NSButton? {
            views(content).compactMap { $0 as? NSButton }.first { $0.title == title }
        }
        func textContains(_ text: String) -> Bool {
            views(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains(text) }
        }
        func press(_ code: Int, _ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: UInt16(code))!
            app.sendEvent(event)
            settle()
        }
        func capture(_ name: String) throws {
            content.layoutSubtreeIfNeeded()
            guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                throw NSError(domain: "PathPopUITests", code: 2)
            }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/tests/\(name).png"))
        }
        check("settings window contains current shortcut", textContains("⌃⌥⌘R"))
        check("settings window has record and restore controls", button("录制") != nil && button("恢复默认") != nil)
        try capture("shortcut-settings-idle")
        guard window.isKeyWindow else {
            throw NSError(domain: "PathPopUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "窗口无法取得键盘焦点，需要可访问的 macOS 桌面窗口服务。"])
        }
        button("录制")?.performClick(nil)
        check("record button enters recording state", controller.isRecording && button("取消录制") != nil)
        press(kVK_ANSI_R)
        check("bare key shows inline error and keeps recording", controller.isRecording && textContains("请至少同时按住") && defaults.writes == 0)
        try capture("shortcut-settings-invalid")
        press(kVK_ANSI_R, .option, repeatKey: true)
        check("repeat does not commit recording", controller.isRecording && defaults.writes == 0)
        press(kVK_Escape)
        check("Esc cancels without changing preferences", !controller.isRecording && hotKey.shortcut == .default && defaults.writes == 0)
        button("录制")?.performClick(nil)
        press(kVK_ANSI_R, .option)
        check("recorded shortcut saves and refreshes window", !controller.isRecording && hotKey.shortcut.displayName == "⌥R" && textContains("已保存 ⌥R") && changes == 1)
        button("录制")?.performClick(nil)
        controller.recordCurrentShortcutIfNeeded()
        check("current Carbon shortcut completes recording", !controller.isRecording && hotKey.shortcut.displayName == "⌥R")
        button("录制")?.performClick(nil)
        press(kVK_ANSI_Q, .command)
        check("Command Q is rejected without changing active shortcut", controller.isRecording && hotKey.shortcut.displayName == "⌥R" && textContains("常用的编辑或系统操作"))
        button("恢复默认")?.performClick(nil)
        check("restore button applies default", hotKey.shortcut == .default && textContains("已保存 ⌃⌥⌘R"))

        backend.registrationResults = [OSStatus(eventHotKeyExistsErr), noErr]
        button("录制")?.performClick(nil)
        press(kVK_ANSI_R, .option)
        check("conflict shows alert and restores original", window.attachedSheet != nil && hotKey.isRegistered && hotKey.shortcut == .default)
        if let sheet = window.attachedSheet {
            let labels = views(sheet.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue).joined()
            check("conflict sheet explains rollback", labels.contains("已恢复原快捷键") && labels.contains("OSStatus"))
            views(sheet.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "好" }?.performClick(nil)
            settle()
        }
        button("录制")?.performClick(nil)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        check("losing focus cancels recording", !controller.isRecording)
        button("录制")?.performClick(nil)
        controller.close()
        check("closing window cancels recording", !controller.isRecording)
        controller.present()
        settle()
        check("settings window can reopen", window.isVisible && !controller.isRecording)
    }

    static func pathConfirmationWindowTests() throws {
        let app = NSApplication.shared
        let paths = ["/tmp/a.txt", "/Users/example/我的文档/" + String(repeating: "较长的文件夹名称/", count: 6) + "report final.pdf"]
        let (alert, choice) = AppDelegate.pathConfirmation(paths: paths)
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        guard let popup = views(choice).compactMap({ $0 as? NSPopUpButton }).first else {
            check("multiple candidate chooser exists", false)
            return
        }
        check("all candidates available for explicit choice", popup.numberOfItems == paths.count)
        popup.selectItem(at: 1)
        app.sendAction(popup.action!, to: popup.target, from: popup)
        check("selected candidate is the chosen path", choice.selectedPath == paths[1])
        check("full long path is visible in selectable label", views(choice).compactMap { $0 as? NSTextView }.contains { $0.string == paths[1] && $0.isSelectable && !$0.isEditable })
        check("confirmation has explicit cancel", alert.buttons.contains { $0.title == "取消" && $0.keyEquivalent == "\u{1b}" })
        alert.layout()
        let content = alert.window.contentView!
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/tests/path-confirmation.png"))
        }
        // Exercise native modal cancellation, without ever calling Finder.
        DispatchQueue.main.async { alert.buttons.last?.performClick(nil) }
        check("cancel returns no authorization to reveal", alert.runModal() == .alertSecondButtonReturn)
        let (single, singleChoice) = AppDelegate.pathConfirmation(paths: [paths[0]])
        check("single inferred path still asks for confirmation", single.messageText == "请确认要定位的路径" && singleChoice.selectedPath == paths[0])
    }

    static func main() {
        if let root = ProcessInfo.processInfo.environment["PATHPOP_TEST_PROJECT_ROOT"] {
            guard FileManager.default.changeCurrentDirectoryPath(root) else { exit(EXIT_FAILURE) }
        }
        if CommandLine.arguments.contains("--ui") {
            let app = NSApplication.shared
            let delegate = UITestApplicationDelegate()
            app.setActivationPolicy(.accessory)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        runSuite()
    }

    static func runSuite() {
        parserTests()
        var tests = [("selection", selectionTests), ("filesystem", filesystemTests), ("shortcut values", shortcutValueTests), ("shortcut transactions", shortcutTransactionTests)]
        // Optional integration tests require an unrestricted logged-in GUI session.
        // Keep the deterministic parser suite runnable in a CLI sandbox or CI.
        if CommandLine.arguments.contains("--desktop") {
            tests += [("selection clipboard isolation", selectionClipboardTests), ("hotkey", hotKeyTests)]
        }
        if CommandLine.arguments.contains("--ui") {
            tests += [("settings window", settingsWindowTests), ("path confirmation", pathConfirmationWindowTests)]
        }
        for (name, test) in tests {
            do { try test() } catch {
                check("\(name) tests complete", false)
                print("  \(error)")
            }
        }
        print("\n\(passed) passed, \(failed) failed")
        exit(failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
