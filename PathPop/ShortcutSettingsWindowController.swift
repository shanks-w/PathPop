import AppKit

extension HotKeyModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: Self = []
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let hotKey: GlobalHotKey
    private let onChange: () -> Void
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let recordButton = NSButton(title: "录制", target: nil, action: nil)
    private var eventMonitor: Any?
    private(set) var isRecording = false

    init(hotKey: GlobalHotKey, onChange: @escaping () -> Void) {
        self.hotKey = hotKey
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 248),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "PathPop · 设置快捷键"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refreshShortcut()
        if !isRecording { setStatus(idleMessage) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private var idleMessage: String {
        hotKey.isRegistered ? "点击“录制”，按下组合键后立即保存。" : "当前快捷键未注册，请重新录制或恢复默认。"
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "定位选中文本的全局快捷键")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutLabel.font = .systemFont(ofSize: 26, weight: .medium)
        shortcutLabel.setAccessibilityLabel("当前快捷键")
        let help = NSTextField(wrappingLabelWithString: "至少包含 ⌘ / ⌥ / ⌃ 中的一个修饰键，可搭配 ⇧。复制、粘贴、退出等常用组合不可用。按 Esc 取消。")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.setAccessibilityElement(true)

        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.bezelStyle = .rounded
        let restore = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefault))
        restore.bezelStyle = .rounded
        restore.toolTip = "恢复为 \(HotKeyShortcut.default.displayName)"
        let done = NSButton(title: "完成", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let spacer = NSView()
        let buttons = NSStackView(views: [recordButton, restore, spacer, done])
        buttons.spacing = 8
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [title, shortcutLabel, help, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshShortcut()
        setStatus(idleMessage)
    }

    private func refreshShortcut() {
        shortcutLabel.stringValue = hotKey.shortcut.displayName
        shortcutLabel.setAccessibilityValue(hotKey.shortcut.displayName)
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    @objc private func toggleRecording() {
        if isRecording { cancelRecording(); return }
        isRecording = true
        recordButton.title = "取消录制"
        setStatus("正在录制… 请按下组合键，或按 Esc 取消。")
        // Local monitoring needs no extra privacy permission, and consumes ⌘Q/⌘W
        // before AppKit interprets them as menu commands while recording.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, self.window?.isKeyWindow == true,
                  self.window?.attachedSheet == nil else { return event }
            if !event.isARepeat {
                self.handleRecordingResult(HotKeyShortcut.recordingResult(
                    keyCode: UInt32(event.keyCode), modifiers: HotKeyModifiers(eventFlags: event.modifierFlags)
                ))
            }
            return nil
        }
    }

    private func handleRecordingResult(_ result: HotKeyShortcut.RecordingResult) {
        switch result {
        case .cancelled: cancelRecording()
        case .ignored: break
        case .invalid(let error): setStatus(error.detail, isError: true)
        case .shortcut(let shortcut): apply(shortcut)
        }
    }

    /// The existing shortcut is consumed by Carbon, so it may not produce a
    /// local keyDown. Route its callback here instead of triggering path capture.
    func recordCurrentShortcutIfNeeded() {
        guard isRecording, window?.isKeyWindow == true else { return }
        apply(hotKey.shortcut)
    }

    private func stopRecording() {
        isRecording = false
        recordButton.title = "录制"
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func cancelRecording() {
        guard isRecording else { return }
        stopRecording()
        setStatus("已取消录制，快捷键未更改。")
    }

    private func apply(_ shortcut: HotKeyShortcut) {
        stopRecording()
        do {
            try hotKey.register(shortcut)
            setStatus("已保存 \(hotKey.shortcut.displayName)，立即生效。")
        } catch {
            setStatus(hotKey.isRegistered ? "未能更改快捷键，原快捷键仍可使用。" : "全局快捷键不可用，请重新录制或恢复默认。", isError: true)
            let alert = NSAlert()
            alert.window.title = "PathPop"
            alert.messageText = "快捷键设置失败"
            alert.informativeText = GlobalHotKey.detail(for: error)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            if let window { alert.beginSheetModal(for: window) }
        }
        refreshShortcut()
        onChange()
    }

    @objc private func restoreDefault() { apply(.default) }
    @objc private func finish() { cancelRecording(); close() }
    func windowWillClose(_ notification: Notification) { cancelRecording() }
    func windowDidResignKey(_ notification: Notification) { cancelRecording() }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
