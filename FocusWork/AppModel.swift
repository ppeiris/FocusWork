import Foundation
import Combine
#if os(macOS)
import AppKit
import Darwin
#endif

final class AppModel: ObservableObject {
    let taskStore: TaskStore
    @Published var pomodoroSettings: PomodoroSettings {
        didSet { saveSettings(); pomodoro.updateSettings(pomodoroSettings) }
    }

    @Published var floatingAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(floatingAlwaysOnTop, forKey: Keys.alwaysOnTop)
            FloatingPanelController.shared.setAlwaysOnTop(floatingAlwaysOnTop)
        }
    }

    @Published var floatingOpacity: Double = 0.92 {
        didSet {
            let clamped = min(1, max(0.35, floatingOpacity))
            if clamped != floatingOpacity {
                floatingOpacity = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.opacity)
            FloatingPanelController.shared.setOpacity(clamped)
        }
    }

    let pomodoro: PomodoroEngine

    #if os(macOS)
    /// Keeps `DispatchSourceSignal` handlers alive for the app lifetime.
    private var shutdownSignalSources: [DispatchSourceSignal] = []
    private var didPersistForExit = false
    #endif

    private static let settingsStorageKey = "focuswork.pomodoroSettings"
    private enum Keys {
        static let alwaysOnTop = "focuswork.floating.alwaysOnTop"
        static let opacity = "focuswork.floating.opacity"
    }

    init() {
        let loaded: PomodoroSettings
        if let data = UserDefaults.standard.data(forKey: Self.settingsStorageKey),
           let s = try? JSONDecoder().decode(PomodoroSettings.self, from: data) {
            loaded = s
        } else {
            loaded = .default
        }
        self.taskStore = TaskStore()
        self.pomodoro = PomodoroEngine(settings: loaded)
        self.pomodoro.taskStore = self.taskStore
        self.pomodoroSettings = loaded
        let onTop = UserDefaults.standard.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        self.floatingAlwaysOnTop = onTop
        let op = UserDefaults.standard.object(forKey: Keys.opacity) as? Double ?? 0.92
        self.floatingOpacity = min(1, max(0.35, op))
        self.taskStore.onWillChangeActiveTask = { [weak self] in
            self?.pomodoro.pause()
        }
        self.taskStore.onDidChangeActiveTask = { [weak self] in
            self?.pomodoro.refreshRemainingFromActiveTask()
        }
        self.taskStore.onDidReloadFromStorage = { [weak self] in
            self?.pomodoro.refreshRemainingFromActiveTask()
        }
        self.pomodoro.refreshRemainingFromActiveTask()
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.persistBeforeTermination()
        }
        // `kill <pid>` (SIGTERM) and Ctrl+C in a terminal (SIGINT) do not always post `willTerminate`; handle them explicitly.
        // `kill -9` / Force Quit cannot be intercepted by any app.
        for sig in [SIGTERM, SIGINT] {
            Darwin.signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.persistBeforeTermination()
                _exit(Int32(128) + sig)
            }
            source.resume()
            shutdownSignalSources.append(source)
        }
        #endif
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(pomodoroSettings) {
            UserDefaults.standard.set(data, forKey: Self.settingsStorageKey)
        }
    }

    func applyFloatingWindowPreferences() {
        FloatingPanelController.shared.setAlwaysOnTop(floatingAlwaysOnTop)
        FloatingPanelController.shared.setOpacity(floatingOpacity)
    }

    /// Persists focus timer progress into task rows and rewrites vault markdown (same fields as normal save) before the process exits.
    func persistBeforeTermination() {
        #if os(macOS)
        guard !didPersistForExit else { return }
        didPersistForExit = true
        #endif
        pomodoro.persistUncommittedStateBeforeTermination()
        taskStore.persistAllToStorage()
    }
}
