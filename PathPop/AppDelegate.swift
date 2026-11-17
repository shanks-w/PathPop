import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = GlobalHotKey()
    private let selectedTextReader = SelectedTextReader()
    private var clipboardMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
    private var shortcutMenuItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var shortcutSettings: ShortcutSettingsWindowController?
    private var isCapturing = false
    private var isPresentingAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            if NSApp.isActive && self.shortcutSettings?.window?.isVisible == true {
                self.shortcutSettings?.recordCurrentShortcutIfNeeded()
            } else {
                self.revealSelection()
            }
        }
        var hotKeyFailure: String?
        do {
            try hotKey.register()
        } catch let error as GlobalHotKey.RegistrationError {
            hotKeyFailure = error.detail
        } catch {
            hotKeyFailure = error.localizedDescription
        }

        refreshShortcutDisplay()
        if let hotKeyFailure {
            showAlert(title: "全局热键不可用", detail: "\(hotKeyFailure)\n\n当前设置：\(hotKey.shortcut.displayName)。请在菜单中选择“设置快捷键…”重新录制或恢复默认。仍可使用“从剪贴板定位路径”。")
        }

        if !AccessibilityPermission.isTrusted(prompt: true) {
            showPermissionHelp()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? hotKey.unregister()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "folder.badge.magnifyingglass", accessibilityDescription: "PathPop")
            button.image?.isTemplate = true
            if button.image == nil { button.title = "PP" }
            button.toolTip = "PathPop · 选中文本后按 \(hotKey.shortcut.displayName) 在 Finder 定位"
        }
        let menu = NSMenu(title: "PathPop")
        menu.autoenablesItems = false
        shortcutMenuItem = NSMenuItem(title: "定位选中文本：\(hotKey.shortcut.displayName)", action: nil, keyEquivalent: "")
        shortcutMenuItem.isEnabled = false
        menu.addItem(shortcutMenuItem)
        settingsMenuItem = makeMenuItem("设置快捷键…", action: #selector(showShortcutSettings))
        menu.addItem(settingsMenuItem)
        menu.addItem(.separator())
        clipboardMenuItem = makeMenuItem("从剪贴板定位路径", action: #selector(revealClipboard))
        menu.addItem(clipboardMenuItem)
        permissionMenuItem = makeMenuItem("检查辅助功能权限", action: #selector(checkPermission))
        menu.addItem(permissionMenuItem)
        menu.addItem(.separator())
        quitMenuItem = makeMenuItem("退出 PathPop", action: #selector(quit), keyEquivalent: "q")
        menu.addItem(quitMenuItem)
        statusItem.menu = menu
    }

    private func makeMenuItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshShortcutDisplay() {
        let name = hotKey.shortcut.displayName
        shortcutMenuItem.title = hotKey.isRegistered ? "定位选中文本：\(name)" : "快捷键不可用：\(name)"
        statusItem.button?.toolTip = hotKey.isRegistered
            ? "PathPop · 选中文本后按 \(name) 在 Finder 定位"
            : "PathPop · 快捷键 \(name) 不可用，请设置快捷键"
    }

    @objc private func showShortcutSettings() {
        guard !isCapturing, !isPresentingAlert else { return }
        if shortcutSettings == nil {
            shortcutSettings = ShortcutSettingsWindowController(hotKey: hotKey) { [weak self] in
                self?.refreshShortcutDisplay()
            }
        }
        shortcutSettings?.present()
    }

    private func revealSelection() {
        guard !isCapturing, !isPresentingAlert else { return }
        guard AccessibilityPermission.isTrusted() else {
            showPermissionHelp()
            return
        }
        setCapturing(true)
        selectedTextReader.capture { [weak self] result in
            guard let self else { return }
            self.setCapturing(false)
            switch result {
            case .success(let text): self.revealPath(in: text)
            case .failure(let failure): self.showCaptureFailure(failure)
            }
        }
    }

    private func setCapturing(_ capturing: Bool) {
        isCapturing = capturing
        clipboardMenuItem.isEnabled = !capturing
        permissionMenuItem.isEnabled = !capturing
        settingsMenuItem.isEnabled = !capturing
        // Finish reading the selection before changing app state.
        quitMenuItem.isEnabled = !capturing
    }

    @objc private func revealClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showAlert(title: "剪贴板没有文本", detail: "请先复制一段包含本地路径的文字，再使用此菜单。\n\n解析路径：无。")
            return
        }
        revealPath(in: text)
    }

    private func revealPath(in text: String) {
        let result = PathExtractor.extract(
            from: text,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
        switch result {
        case .success(let url):
            // Only ask Finder to select the item. Never open it or invoke Quick Look.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failure(.confirmationRequired(let paths)):
            confirmPath(paths)
        case .failure(.emptyText):
            showAlert(title: "没有选中文本", detail: "请选中包含本地路径的文字后重试。\n\n解析路径：无。")
        case .failure(.noPathFound):
            showAlert(title: "没有找到本地路径", detail: "支持 / 开头的绝对路径、~/ 和 file:// URL。\n\n解析路径：无。\n选中文本：\(String(text.prefix(500)))")
        case .failure(.pathsDoNotExist(let paths)):
            let shownPaths = paths.prefix(12).joined(separator: "\n")
            let remaining = paths.count > 12 ? "\n（另有 \(paths.count - 12) 个候选未显示）" : ""
            showAlert(title: "路径不存在或无法访问", detail: "未找到可定位的文件或文件夹，请确认路径和磁盘访问权限。\n\n解析出的路径（按尝试顺序）：\n\(shownPaths)\(remaining)")
        }
    }

    private func confirmPath(_ paths: [String]) {
        guard !isPresentingAlert, !paths.isEmpty else { return }
        isPresentingAlert = true
        let (alert, choice) = Self.pathConfirmation(paths: paths)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        isPresentingAlert = false
        guard response == .alertFirstButtonReturn else { return }
        let path = choice.selectedPath
        guard FileManager.default.fileExists(atPath: path) else {
            showAlert(title: "路径已不存在或无法访问", detail: path)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func pathConfirmation(paths: [String]) -> (NSAlert, PathConfirmationView) {
        let alert = NSAlert()
        alert.window.title = "PathPop"
        alert.messageText = paths.count > 1 ? "请选择要定位的路径" : "请确认要定位的路径"
        alert.informativeText = "以下路径由选中文字推测得出。确认后才会在 Finder 中定位。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "在 Finder 中定位")
        let cancel = alert.addButton(withTitle: "取消")
        cancel.keyEquivalent = "\u{1b}"
        let choice = PathConfirmationView(paths: paths)
        alert.accessoryView = choice
        return (alert, choice)
    }

    @objc private func checkPermission() {
        if AccessibilityPermission.isTrusted(prompt: true) {
            showAlert(title: "辅助功能权限已授予", detail: "在其他应用中选中含路径的文字，按 \(hotKey.shortcut.displayName)，即可在 Finder 定位。", style: .informational)
        } else {
            showPermissionHelp()
        }
    }

    private func showPermissionHelp() {
        showAlert(
            title: "需要辅助功能权限",
            detail: "PathPop 需要通过辅助功能读取所选文字，不会改写剪贴板。\n\n请前往“系统设置 → 隐私与安全性 → 辅助功能”，添加并开启 PathPop，然后重新启动应用。\n\n当前尚未读取选中文本；解析路径：无。无需授权也可使用“从剪贴板定位路径”。",
            settingsButton: true
        )
    }

    private func showCaptureFailure(_ failure: SelectedTextReader.Failure) {
        let title: String
        let detail: String
        switch failure {
        case .permissionRequired:
            showPermissionHelp()
            return
        case .frontmostAppChanged:
            title = "选中文本所在应用已切换"
            detail = "请保持原应用在前台，选中文字后重新按快捷键。"
        case .selectionUnavailable:
            title = "当前应用不支持直接读取选中文字"
            detail = "请手动复制路径，然后点击菜单栏中的“从剪贴板定位路径”。PathPop 不会自动复制或改写剪贴板。"
        case .noText:
            title = "没有选中文字"
            detail = "请先选中路径文字，再按快捷键；也可以手动复制后使用“从剪贴板定位路径”。"
        }
        showAlert(title: title, detail: detail + "\n\n解析路径：无（未开始解析）。")
    }

    private func showAlert(
        title: String,
        detail: String,
        style: NSAlert.Style = .warning,
        settingsButton: Bool = false
    ) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        let alert = NSAlert()
        alert.window.title = "PathPop"
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = style
        alert.addButton(withTitle: settingsButton ? "打开辅助功能设置" : "好")
        if settingsButton { alert.addButton(withTitle: "稍后") }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        isPresentingAlert = false
        if settingsButton, response == .alertFirstButtonReturn,
           !AccessibilityPermission.openSettings() {
            showAlert(title: "无法打开系统设置", detail: "请手动打开“系统设置 → 隐私与安全性 → 辅助功能”，添加并开启 PathPop。")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// Native chooser keeps the full selected path visible, even when menu titles truncate.
final class PathConfirmationView: NSStackView {
    private let paths: [String]
    private let popup = NSPopUpButton()
    private let pathText = NSTextView()
    var selectedPath: String { paths[max(0, popup.indexOfSelectedItem)] }

    init(paths: [String]) {
        precondition(!paths.isEmpty)
        self.paths = paths
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 100))
        orientation = .vertical
        alignment = .leading
        spacing = 8
        popup.addItems(withTitles: paths)
        popup.setAccessibilityLabel("待定位的路径")
        popup.target = self
        popup.action = #selector(selectionChanged)
        if paths.count > 1 { addArrangedSubview(popup) }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        pathText.isEditable = false
        pathText.isSelectable = true
        pathText.font = .systemFont(ofSize: 13)
        pathText.textContainerInset = NSSize(width: 6, height: 6)
        pathText.isVerticallyResizable = true
        pathText.isHorizontallyResizable = false
        pathText.autoresizingMask = [.width]
        pathText.textContainer?.widthTracksTextView = true
        pathText.textContainer?.lineBreakMode = .byCharWrapping
        pathText.setAccessibilityLabel("完整路径")
        scroll.documentView = pathText
        addArrangedSubview(scroll)
        widthAnchor.constraint(equalToConstant: 520).isActive = true
        scroll.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        if paths.count > 1 { popup.widthAnchor.constraint(equalTo: widthAnchor).isActive = true }
        selectionChanged()
        frame.size.height = fittingSize.height
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func selectionChanged() {
        pathText.string = selectedPath
        pathText.scrollRangeToVisible(NSRange(location: 0, length: 0))
        popup.toolTip = selectedPath
    }
}
