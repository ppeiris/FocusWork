import Foundation
import Combine

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
        self.pomodoroSettings = loaded
        let onTop = UserDefaults.standard.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        self.floatingAlwaysOnTop = onTop
        let op = UserDefaults.standard.object(forKey: Keys.opacity) as? Double ?? 0.92
        self.floatingOpacity = min(1, max(0.35, op))
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
}
