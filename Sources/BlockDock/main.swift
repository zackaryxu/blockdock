import AppKit
import BlockDockCore
import Darwin
import SwiftUI

@MainActor final class AppState: ObservableObject {
    @Published private(set) var document: BlockDocument
    @Published private(set) var now: Date
    @Published var errorMessage: String?
    let engine: BlockEngine

    init(engine: BlockEngine) {
        self.engine = engine
        document = engine.document
        now = Date()
    }

    func tick() {
        now = Date()
        do {
            try engine.reconcile(at: now)
            document = engine.document
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        document = engine.document
    }

    func start(_ category: String, minutes: Int) {
        perform {
            if engine.document.pending != nil { try engine.answer(category: category, minutes: minutes, at: Date()) }
            else { try engine.start(category: category, minutes: minutes, at: Date()) }
        }
    }

    func stop() { perform { try engine.stop(at: Date()) } }
    func dismiss() { perform { try engine.dismissDecision() } }
    func add(_ category: String) { perform { try engine.addCategory(category) } }
    func remove(_ category: String) { perform { try engine.removeCategory(category) } }
}

private enum Style {
    static let background = Color(red: 0.075, green: 0.09, blue: 0.12)
    static let card = Color(red: 0.13, green: 0.16, blue: 0.2)
    static let accent = Color(red: 0.42, green: 0.79, blue: 0.73)
    static let secondary = Color(red: 0.66, green: 0.71, blue: 0.75)
}

private func durationText(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "\(Int(ceil(max(0, seconds))))s" }
    let minutes = Int(max(0, seconds) / 60)
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

private struct PickerView: View {
    @ObservedObject var state: AppState
    @State private var chosen = ""
    @State private var duration = "25"

    private var minutes: Int? {
        guard let value = Int(duration.trimmingCharacters(in: .whitespaces)),
              (1...240).contains(value) else { return nil }
        return value
    }

    private var selected: String {
        state.document.categories.contains(chosen) ? chosen : (state.document.categories.first ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let pending = state.document.pending {
                Text("Block finished").font(.title2.bold())
                Text("\(pending.category) ended at \(pending.expiredAt.formatted(date: .omitted, time: .shortened)).")
                    .foregroundStyle(Style.secondary)
            } else {
                Text("New block").font(.title2.bold())
            }

            Picker("Category", selection: Binding(get: { selected }, set: { chosen = $0 })) {
                ForEach(state.document.categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)

            HStack {
                Text("Duration")
                TextField("1–240", text: $duration)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .accessibilityLabel("Duration in minutes")
                    .help("Enter a whole number from 1 to 240.")
                Text("minutes")
            }

            HStack {
                if let pending = state.document.pending {
                    Button("Continue") {
                        if let minutes { state.start(pending.category, minutes: minutes) }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Style.accent)
                        .disabled(minutes == nil || !state.document.categories.contains(pending.category))
                    Button("Switch category") {
                        if let minutes { state.start(selected, minutes: minutes) }
                    }
                        .disabled(minutes == nil || selected.isEmpty || pending.category == selected)
                    Spacer()
                    Button("Stop for now") { state.dismiss() }
                } else {
                    Button("Start block") {
                        if let minutes { state.start(selected, minutes: minutes) }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Style.accent)
                        .disabled(minutes == nil || selected.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RunningView: View {
    @ObservedObject var state: AppState
    let running: RunningBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current block").font(.caption).foregroundStyle(Style.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(running.category).font(.title2.bold())
                Spacer()
                Text(durationText(state.engine.secondsRemaining(at: state.now)))
                    .font(.title2)
                    .monospacedDigit()
            }
            HStack {
                Text("Started \(running.startedAt.formatted(date: .omitted, time: .shortened)) · Ends \(running.endsAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(Style.secondary)
                Spacer()
                Button("End block") { state.stop() }
            }
        }
        .padding(24)
        .background(Style.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let totals = state.engine.totals(for: state.now, includingRunningAt: state.now)
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.title2.bold())
                Spacer()
                Text(durationText(totals.values.reduce(0, +))).font(.title2.monospacedDigit())
            }
            if totals.isEmpty {
                Text("No time recorded today.").foregroundStyle(Style.secondary)
            } else {
                ForEach(totals.keys.sorted(), id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        Text(durationText(totals[category] ?? 0)).monospacedDigit()
                    }
                }
            }
            Divider()
            DisclosureGroup("Completed blocks") {
                if state.document.history.isEmpty {
                    Text("Finished blocks will appear here.").foregroundStyle(Style.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(state.document.history.sorted { $0.endedAt > $1.endedAt }.prefix(20)) { block in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(block.category).fontWeight(.medium)
                                    Text(block.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(Style.secondary)
                                }
                                Spacer()
                                Text(durationText(block.duration)).monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(24)
        .background(Style.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CategoryView: View {
    @ObservedObject var state: AppState
    @State private var newCategory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add or remove labels for future blocks. Past history keeps its original labels.")
                .font(.caption).foregroundStyle(Style.secondary)
            ForEach(state.document.categories, id: \.self) { category in
                HStack {
                    Text(category)
                    Spacer()
                    Button {
                        state.remove(category)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(category)")
                    .disabled(state.document.categories.count == 1)
                }
            }
            HStack {
                TextField("New category", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func add() {
        state.add(newCategory)
        if state.errorMessage == nil { newCategory = "" }
    }
}

private struct Dashboard: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("BlockDock").font(.title2.bold())
                if let running = state.document.running { RunningView(state: state, running: running) }
                else { PickerView(state: state) }
                if let message = state.errorMessage {
                    Text(message).foregroundStyle(.red).accessibilityLabel("Error: \(message)")
                }
                HistoryView(state: state)
                DisclosureGroup("Edit categories") {
                    CategoryView(state: state).padding(.top, 12)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(Style.background)
        .preferredColorScheme(.dark)
    }
}

private struct Badge: View {
    @ObservedObject var state: AppState
    let showDashboard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.document.running?.category ?? "Decision needed")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(state.document.running == nil ? "Choose the next block" : "Drag to move")
                    .font(.caption2).foregroundStyle(Style.secondary)
            }
            Spacer(minLength: 0)
            if state.document.running != nil {
                Text(durationText(state.engine.secondsRemaining(at: state.now)))
                    .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Button("Open") { showDashboard() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 62)
        .background(Style.card)
        .preferredColorScheme(.dark)
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let options: LaunchOptions
    private struct BadgePosition: Codable { var x: Double; var y: Double }
    private var state: AppState!
    private var window: NSWindow!
    private var badge: NSPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }
    private var badgePositionURL: URL {
        state.engine.fileURL.deletingLastPathComponent().appendingPathComponent("badge-position.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dataDir: URL
        if let explicit = options.dataDirectory {
            dataDir = explicit
        } else {
            dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BlockDock", isDirectory: true)
        }
        do {
            if let demo = options.demo {
                try seedDemo(at: dataDir, expired: demo == .expired)
            }
            let engine = try BlockEngine(dataDirectory: dataDir)
            state = AppState(engine: engine)
            makeMenu()
            makeWindow(saveFrame: options.dataDirectory == nil)
            makeBadge()
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "◷"
            let menu = NSMenu()
            let openItem = NSMenuItem(title: "Open BlockDock", action: #selector(showDashboard), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit BlockDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.onTick() }
            }
            updateBadge()
            if options.renderOutput != nil { window.orderFront(nil) }
            else { window.makeKeyAndOrderFront(nil) }
            if let output = options.renderOutput, let badgeOutput = options.badgeRenderOutput {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    Task { @MainActor in
                        do {
                            try self.capture(self.window.contentView, to: output)
                            try self.capture(self.badge.contentView, to: badgeOutput)
                            NSApp.terminate(nil)
                        } catch {
                            fputs("BlockDock render: \(error.localizedDescription)\n", stderr)
                            exit(EXIT_FAILURE)
                        }
                    }
                }
            }
        } catch {
            fputs("BlockDock: \(error.localizedDescription)\n", stderr)
            if options.renderOutput == nil {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "BlockDock could not open its saved data"
                alert.informativeText = "\(error.localizedDescription)\n\nData folder: \(dataDir.path)\n\nThe saved file has not been reset. Keep a copy of blocks.json before repairing or moving it, then reopen the app."
                alert.addButton(withTitle: "Quit")
                alert.addButton(withTitle: "Show Data Folder")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDir.path)
                }
            }
            exit(EXIT_FAILURE)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func onTick() {
        let wasPending = state.document.pending != nil
        state.tick()
        updateBadge()
        if !wasPending && state.document.pending != nil { showDashboard() }
    }

    private func makeMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        root.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About BlockDock", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit BlockDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = root
    }

    private func makeWindow(saveFrame: Bool) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "BlockDock"
        window.minSize = NSSize(width: 480, height: 420)
        window.center()
        if saveFrame { window.setFrameAutosaveName("BlockDockDashboard") }
        window.contentView = NSHostingView(rootView: Dashboard(state: state))
    }

    private func makeBadge() {
        badge = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 62),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        badge.isFloatingPanel = true
        badge.level = .floating
        badge.isMovableByWindowBackground = true
        badge.hidesOnDeactivate = false
        badge.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        badge.backgroundColor = .clear
        badge.isOpaque = false
        badge.hasShadow = true
        badge.contentView = NSHostingView(rootView: Badge(
            state: state,
            showDashboard: { [weak self] in self?.showDashboard() }
        ))
        if let visible = NSScreen.main?.visibleFrame {
            var origin = NSPoint(x: visible.maxX - 340, y: visible.maxY - 80)
            if let data = try? Data(contentsOf: badgePositionURL),
               let saved = try? JSONDecoder().decode(BadgePosition.self, from: data),
               let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSPoint(x: saved.x, y: saved.y)) }) {
                origin = NSPoint(x: min(saved.x, screen.visibleFrame.maxX - badge.frame.width),
                                 y: min(saved.y, screen.visibleFrame.maxY - badge.frame.height))
            }
            badge.setFrameOrigin(origin)
        }
        badge.delegate = self
    }

    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? NSWindow, moved === badge else { return }
        let position = BadgePosition(x: badge.frame.minX, y: badge.frame.minY)
        if let bytes = try? JSONEncoder().encode(position) {
            try? bytes.write(to: badgePositionURL, options: .atomic)
        }
    }

    private func updateBadge() {
        if state.document.running != nil || state.document.pending != nil {
            if !badge.isVisible { badge.orderFront(nil) }
        } else if badge.isVisible { badge.orderOut(nil) }
    }

    @objc private func showDashboard() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func capture(_ candidate: NSView?, to url: URL) throws {
        guard let view = candidate,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw LaunchError("The app could not capture the requested view.")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw LaunchError("The app could not encode the screenshot.")
        }
        try png.write(to: url, options: .withoutOverwriting)
    }
}

private func seedDemo(at directory: URL, expired: Bool) throws {
    let file = directory.appendingPathComponent("blocks.json")
    guard !FileManager.default.fileExists(atPath: file.path) else { return }
    let now = Date()
    let calendar = Calendar.current
    var doc = BlockDocument()
    doc.history = (1...6).compactMap { daysBack in
        guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now),
              let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) else { return nil }
        return FinishedBlock(category: daysBack.isMultiple(of: 2) ? "Study" : "Work", startedAt: start,
                             endedAt: start.addingTimeInterval(TimeInterval((25 + daysBack * 5) * 60)), plannedMinutes: 60)
    }
    doc.history.append(FinishedBlock(category: "Admin", startedAt: now.addingTimeInterval(-7200),
                                     endedAt: now.addingTimeInterval(-5700), plannedMinutes: 25))
    doc.running = RunningBlock(category: "Work", startedAt: now.addingTimeInterval(expired ? -2400 : -480),
                               endsAt: now.addingTimeInterval(expired ? -900 : 1020), plannedMinutes: 25)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(doc).write(to: file, options: .atomic)
}

let launchOptions: LaunchOptions
do {
    launchOptions = try LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("BlockDock: \(error.localizedDescription)\n", stderr)
    exit(2)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = AppController(options: launchOptions)
    app.delegate = controller
    app.run()
}
