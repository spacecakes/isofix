import AppKit
import Combine
import ServiceManagement

/// All state and behaviour; the settings window is just a view onto it.
final class AppModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: KeyboardID
        let name: String
        let swapApplied: Bool
        let info: KeyboardInfo
        let mode: Mode
    }

    enum Mode: Hashable { case auto, swap, leave }

    /// The last press of § or < shown in the window, to tell what a keyboard actually sends.
    struct Press: Identifiable {
        let id = UUID() // new for every press, so repeats of the same key still register
        let keyboard: String
        let pressed: Detector.Key
        let typed: Detector.Key
        let result: String
        var correct: Bool { pressed == typed }
    }

    /// What `handle` did about a press, for the key test to describe.
    private enum Outcome { case correct, fixed, pinned, skipped }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var monitoring = false
    @Published private(set) var permissionGranted = Detector.hasPermission
    @Published private(set) var launchAtLogin = AppModel.loginEnabled
    @Published private(set) var loginError: String?
    @Published private(set) var lastPress: Press?
    /// Presses are only kept while the window is open, and dropped when it closes.
    var recordsPresses = false { didSet { if !recordsPresses { lastPress = nil } } }
    /// Without the window there is no visible sign the app needs anything or
    /// that it started working, so show it on first run, while monitoring can't
    /// run, and on the launch after a run where it couldn't: the "Quit & Reopen"
    /// after the Input Monitoring grant.
    private(set) var showsWindowAtLaunch = false

    private let mapper = KeyMapper()
    private let detector = Detector()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var pendingReconcile: DispatchWorkItem?
    private static var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private var cooldownUntil: [KeyboardID: Date] = [:]

    private var isFirstRun: Bool { !defaults.bool(forKey: "didOnboard") }

    func start() {
        let firstRun = isFirstRun
        let monitoringFailedLastRun = defaults.bool(forKey: "monitoringFailed")
        if firstRun {
            defaults.set(true, forKey: "didOnboard")
            // "Install and forget": start at login unless the user turns it off.
            setLaunchAtLogin(true)
        }

        detector.onCheck = { [weak self] check in
            guard let self else { return }
            record(check, handle(check))
        }
        detector.onDevicesChanged = { [weak self] in self?.scheduleReconcile() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReconcile()
        }

        if !detector.start() { Detector.requestPermission() }
        // Safety net: re-assert mappings and pick up a late permission grant.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        showsWindowAtLaunch = firstRun || monitoringFailedLastRun || !monitoring
    }

    func refresh() {
        permissionGranted = Detector.hasPermission
        monitoring = detector.start()
        defaults.set(!monitoring, forKey: "monitoringFailed")
        launchAtLogin = Self.loginEnabled
        reconcile()
    }

    /// Device attach/wake: the event-system service shows up a beat after the
    /// IOHIDDevice, and several keyboards attach at once, so coalesce into one pass.
    private func scheduleReconcile() {
        pendingReconcile?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        pendingReconcile = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: Swap state

    private func wantedSwap(_ id: KeyboardID) -> Bool? { defaults.object(forKey: "swap.\(id)") as? Bool }
    /// Per-keyboard opt-out, e.g. for a board whose keycaps really are printed the other way round.
    private func ignored(_ id: KeyboardID) -> Bool { defaults.bool(forKey: "ignore.\(id)") }

    private func apply(_ on: Bool, _ id: KeyboardID) {
        mapper.setSwap(on, for: id)
        defaults.set(on, forKey: "swap.\(id)")
    }

    private func reconcile() {
        var kbs = mapper.keyboards()
        for i in kbs.indices {
            if let want = wantedSwap(kbs[i].id), want != kbs[i].swapApplied {
                mapper.setSwap(want, for: kbs[i].id)
                kbs[i].swapApplied = want
                Detector.log.info("\(kbs[i].id, privacy: .public): re-applied swap=\(want)")
            }
        }
        rebuildRows(kbs)
    }

    /// Rebuilds the published rows; pass `kbs` when already enumerated, and
    /// `changed` to patch one board's swap state without re-reading IOKit.
    private func rebuildRows(_ kbs: [ExternalKeyboard]? = nil, changed: (KeyboardID, Bool)? = nil) {
        let boards = kbs ?? rows.map { ExternalKeyboard(id: $0.id, name: $0.name, swapApplied: $0.swapApplied, info: $0.info) }
        let new = boards.map { kb -> Row in
            let swap = changed?.0 == kb.id ? changed!.1 : kb.swapApplied
            let mode: Mode = ignored(kb.id) ? (swap ? .swap : .leave) : .auto
            return Row(id: kb.id, name: kb.name, swapApplied: swap, info: kb.info, mode: mode)
        }
        if new != rows { rows = new }
    }

    /// Automatic keeps the current swap until the next keypress proves it wrong;
    /// the manual modes pin it and stop detection for that keyboard.
    func setMode(_ mode: Mode, for id: KeyboardID) {
        defaults.set(mode != .auto, forKey: "ignore.\(id)")
        var changed: (KeyboardID, Bool)?
        if mode != .auto {
            apply(mode == .swap, id)
            changed = (id, mode == .swap)
        }
        rebuildRows(changed: changed)
    }

    private func handle(_ check: Detector.Check) -> Outcome {
        let id = check.id
        guard check.verdict == .wrong else { return .correct }
        if ignored(id) { return .pinned }
        if let until = cooldownUntil[id], until > Date() { return .skipped }
        guard let row = rows.first(where: { $0.id == id }) else { return .skipped }
        let on = !row.swapApplied
        apply(on, id)
        cooldownUntil[id] = Date().addingTimeInterval(1)
        Detector.log.notice("\(id, privacy: .public): wrong key detected, swap now \(on)")
        rebuildRows(changed: (id, on))
        return .fixed
    }

    /// Runs after `handle`, so the row already shows any swap it just applied.
    private func record(_ check: Detector.Check, _ outcome: Outcome) {
        guard recordsPresses else { return }
        let row = rows.first { $0.id == check.id }
        let swapped = row?.swapApplied ?? false
        // Whether the key came out right is visible on the key itself; say what ISOFix did.
        let result = switch outcome {
        case .correct: swapped ? "Swapped by ISOFix" : "No swap needed"
        case .fixed: swapped ? "Fixed: now swapped" : "Fixed: swap removed"
        case .pinned: "Not fixed: \(swapped ? "Always swap" : "Don't swap") is selected"
        case .skipped: "Just fixed, press again"
        }
        lastPress = Press(keyboard: row?.name ?? check.id.description,
                          pressed: check.pressed, typed: check.typed, result: result)
    }

    // MARK: Settings

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = Self.loginEnabled
    }

    func requestPermission() {
        Detector.requestPermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
