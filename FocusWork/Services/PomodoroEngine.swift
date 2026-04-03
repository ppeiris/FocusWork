import Foundation
import Combine

enum PomodoroPhase: Equatable {
    case idle
    case work
    case shortBreak
    case longBreak
}

final class PomodoroEngine: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var completedWorkSessions: Int = 0

    private var timer: Timer?
    private var settings: PomodoroSettings

    var settingsSnapshot: PomodoroSettings {
        settings
    }

    init(settings: PomodoroSettings = .default) {
        self.settings = settings
        remainingSeconds = settings.workSeconds
    }

    func updateSettings(_ new: PomodoroSettings) {
        settings = new
        if phase == .idle {
            remainingSeconds = new.workSeconds
        }
    }

    var isRunning: Bool { timer != nil }

    func startOrResume() {
        guard timer == nil else { return }
        if phase == .idle {
            phase = .work
            remainingSeconds = settings.workSeconds
        }
        if remainingSeconds <= 0 {
            advancePhase()
        }
        startTimer()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resetSession() {
        pause()
        phase = .idle
        completedWorkSessions = 0
        remainingSeconds = settings.workSeconds
    }

    /// Skip to the next phase (ends current interval early).
    func skipPhase() {
        pause()
        advancePhase()
        if phase != .idle {
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            finishCurrentPhase()
            return
        }
        remainingSeconds -= 1
        if remainingSeconds == 0 {
            finishCurrentPhase()
        }
    }

    private func finishCurrentPhase() {
        pause()
        advancePhase()
        if phase != .idle {
            startTimer()
        }
    }

    private func advancePhase() {
        switch phase {
        case .idle:
            phase = .work
            remainingSeconds = settings.workSeconds
        case .work:
            completedWorkSessions += 1
            let nextLong = completedWorkSessions > 0 && completedWorkSessions % settings.sessionsUntilLongBreak == 0
            if nextLong {
                phase = .longBreak
                remainingSeconds = settings.longBreakSeconds
            } else {
                phase = .shortBreak
                remainingSeconds = settings.shortBreakSeconds
            }
        case .shortBreak, .longBreak:
            phase = .work
            remainingSeconds = settings.workSeconds
        }
    }
}
