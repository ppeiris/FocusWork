import AppKit
import SwiftUI

struct MenuBarExtraMenuView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var pomodoro: PomodoroEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open FocusWork") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button(pomodoro.isRunning ? "Pause timer" : "Start timer") {
            toggleTimer()
        }
        .keyboardShortcut(.space, modifiers: [.command])

        Button("Skip phase") {
            pomodoro.skipPhase()
        }
        .keyboardShortcut("s", modifiers: [.command])

        Button("Reset session") {
            pomodoro.resetSession()
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("Show floating timer") {
            FloatingPanelController.shared.configureIfNeeded(model: model)
        }
        .keyboardShortcut("f", modifiers: [.command, .option])

        Divider()

        Text(statusLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }

    private func toggleTimer() {
        if pomodoro.isRunning {
            pomodoro.pause()
        } else {
            pomodoro.startOrResume()
        }
    }

    private var statusLine: String {
        let clock = shortDuration(max(0, pomodoro.remainingSeconds))
        switch pomodoro.phase {
        case .idle:
            return "Idle · \(clock)"
        case .work:
            return pomodoro.isRunning ? "Focus · \(clock) left" : "Paused · \(clock) left"
        case .workOvertime:
            return "Overtime · +\(clock)"
        case .shortBreak:
            return pomodoro.isRunning ? "Short break · \(clock)" : "Paused · \(clock)"
        case .longBreak:
            return pomodoro.isRunning ? "Long break · \(clock)" : "Paused · \(clock)"
        }
    }

    private func shortDuration(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return "\(h):" + String(format: "%02d:%02d", m, s)
        }
        return "\(m):" + String(format: "%02d", s)
    }
}
