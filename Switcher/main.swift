import AppKit
import Carbon

// MARK: - App Entry

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: SwitcherPanel!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        panel = SwitcherPanel()

        // Status bar icon with menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "⌘"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Search", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Switcher", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        // Global hotkey: Cmd+Space
        registerHotkey()

        // Also support Cmd+Space alternative: Option+Space
        registerAltHotkey()
    }

    @objc func togglePanel() {
        panel.toggle()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Global Hotkey (Carbon)

    func registerHotkey() {
        // Cmd+Space
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5357_4348), id: 1) // "SWCH"
        let modifiers: UInt32 = UInt32(cmdKey)
        let keyCode: UInt32 = 49 // Space

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            DispatchQueue.main.async {
                guard let del = NSApp.delegate as? AppDelegate else { return }
                del.togglePanel()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Cmd+Space hotkey registration failed (status: \(status)). Spotlight may be using it.")
            print("Disable Spotlight hotkey in System Settings > Keyboard > Shortcuts, or use Option+Space.")
        }
    }

    func registerAltHotkey() {
        // Option+Space
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5357_4332), id: 2) // "SWC2"
        let modifiers: UInt32 = UInt32(optionKey)
        let keyCode: UInt32 = 49 // Space

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Reuse the existing handler installed above
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - Floating Panel

class SwitcherPanel: NSPanel {
    let searchField = NSTextField()
    let resultsView = ResultsView()
    var allApps: [AppEntry] = []

    init() {
        let width: CGFloat = 600
        let height: CGFloat = 360

        // Center on screen
        let screen = NSScreen.main!.frame
        let rect = NSRect(
            x: (screen.width - width) / 2,
            y: (screen.height - height) / 2 + 100,
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        isOpaque = false
        backgroundColor = NSColor(white: 0.12, alpha: 0.95)
        hasShadow = true

        // Rounded corners
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true

        setupUI()
        loadApps()
    }

    func setupUI() {
        guard let content = contentView else { return }

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search apps..."
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 24, weight: .light)
        searchField.textColor = .white
        searchField.backgroundColor = .clear
        searchField.drawsBackground = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = resultsView

        let placeholder = NSMutableAttributedString(string: "Search apps...", attributes: [
            .foregroundColor: NSColor(white: 1.0, alpha: 0.35),
            .font: NSFont.systemFont(ofSize: 24, weight: .light)
        ])
        searchField.placeholderAttributedString = placeholder

        content.addSubview(searchField)

        // Separator
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator
        content.addSubview(sep)

        // Results scroll view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = resultsView
        resultsView.panel = self
        content.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            sep.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            sep.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            sep.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    func loadApps() {
        allApps = []

        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]

        let fm = FileManager.default
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(item)
                let name = (item as NSString).deletingPathExtension
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 32, height: 32)
                allApps.append(AppEntry(name: name, path: path, icon: icon))
            }
        }

        // Deduplicate by name (prefer /Applications over /System/Applications)
        var seen = Set<String>()
        allApps = allApps.filter { seen.insert($0.name).inserted }
        allApps.sort {
            let a = SwitcherPanel.priorityApps.contains($0.name.lowercased())
            let b = SwitcherPanel.priorityApps.contains($1.name.lowercased())
            if a != b { return a }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        resultsView.updateResults(allApps)
    }

    static let priorityApps: Set<String> = [
        "terminal", "firefox", "microsoft word", "microsoft excel",
        "microsoft outlook", "microsoft powerpoint", "visual studio code", "codex",
    ]

    @objc func searchChanged() {
        let query = searchField.stringValue.lowercased()
        if query.isEmpty {
            resultsView.updateResults(allApps)
            return
        }

        // Score and sort by match quality, with priority boost
        var scored: [(app: AppEntry, score: Int)] = []
        for app in allApps {
            let name = app.name.lowercased()
            var score = 0
            if name == query {
                score = 100
            } else if name.hasPrefix(query) {
                score = 80
            } else if name.contains(query) {
                score = 60
            } else if fuzzyMatch(query: query, target: name) {
                score = 40
            }
            if score > 0 {
                if SwitcherPanel.priorityApps.contains(name) {
                    score += 10
                }
                scored.append((app, score))
            }
        }
        scored.sort { $0.score > $1.score }
        resultsView.updateResults(scored.map(\.app))
    }

    func fuzzyMatch(query: String, target: String) -> Bool {
        var qi = query.startIndex
        var ti = target.startIndex
        while qi < query.endIndex && ti < target.endIndex {
            if query[qi] == target[ti] {
                qi = query.index(after: qi)
            }
            ti = target.index(after: ti)
        }
        return qi == query.endIndex
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        searchField.stringValue = ""
        searchChanged()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(searchField)
    }

    func hide() {
        orderOut(nil)
    }

    func launchSelected() {
        guard let app = resultsView.selectedApp else { return }
        hide()
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
    }

    // Allow Escape to close
    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    // Keep panel key when clicking outside
    override var canBecomeKey: Bool { true }
}

// MARK: - Data Model

struct AppEntry {
    let name: String
    let path: String
    let icon: NSImage
}

// MARK: - Results View

class ResultsView: NSView, NSTextFieldDelegate {
    var entries: [AppEntry] = []
    var selectedIndex = 0
    var rows: [RowView] = []
    weak var panel: SwitcherPanel?

    func updateResults(_ apps: [AppEntry]) {
        entries = apps
        selectedIndex = 0
        rebuild()
        // Scroll to top
        if let scrollView = enclosingScrollView {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: frame.height - scrollView.contentView.bounds.height))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    var selectedApp: AppEntry? {
        guard selectedIndex >= 0 && selectedIndex < entries.count else { return nil }
        return entries[selectedIndex]
    }

    func rebuild() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []

        let rowHeight: CGFloat = 40
        let totalHeight = CGFloat(entries.count) * rowHeight
        let parentHeight = enclosingScrollView?.frame.height ?? 300

        frame = NSRect(x: 0, y: 0, width: enclosingScrollView?.frame.width ?? 600, height: max(totalHeight, parentHeight))

        for (i, app) in entries.enumerated() {
            let y = frame.height - CGFloat(i + 1) * rowHeight
            let row = RowView(frame: NSRect(x: 0, y: y, width: frame.width, height: rowHeight))
            row.setup(app: app, selected: i == selectedIndex, index: i)
            row.resultsView = self
            addSubview(row)
            rows.append(row)
        }
    }

    func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let old = selectedIndex
        selectedIndex = max(0, min(entries.count - 1, selectedIndex + delta))
        if old != selectedIndex {
            if old < rows.count { rows[old].setSelected(false) }
            if selectedIndex < rows.count {
                rows[selectedIndex].setSelected(true)
                rows[selectedIndex].scrollToVisible(rows[selectedIndex].bounds)
            }
        }
    }

    // Intercept arrow keys and enter in the search field
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(-1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(1)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            panel?.launchSelected()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            panel?.hide()
            return true
        }
        return false
    }

    // NSTextField delegate for live search
    func controlTextDidChange(_ obj: Notification) {
        panel?.searchChanged()
    }
}

// MARK: - Row View

class RowView: NSView {
    let iconView = NSImageView()
    let label = NSTextField(labelWithString: "")
    var index = 0
    weak var resultsView: ResultsView?

    func setup(app: AppEntry, selected: Bool, index: Int) {
        self.index = index
        autoresizingMask = [.width]

        iconView.image = app.icon
        iconView.frame = NSRect(x: 16, y: 4, width: 32, height: 32)
        addSubview(iconView)

        label.stringValue = app.name
        label.font = NSFont.systemFont(ofSize: 16)
        label.textColor = .white
        label.frame = NSRect(x: 58, y: 8, width: frame.width - 74, height: 24)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        wantsLayer = true
        setSelected(selected)
    }

    func setSelected(_ sel: Bool) {
        layer?.cornerRadius = 6
        if sel {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        resultsView?.selectedIndex = index
        resultsView?.rebuild()
        resultsView?.panel?.launchSelected()
    }
}

// MARK: - Run

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
