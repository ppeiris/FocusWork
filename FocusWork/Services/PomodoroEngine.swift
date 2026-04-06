import Foundation
import Combine

enum PomodoroPhase: Equatable {
    case idle
    case work
    case workOvertime
    case shortBreak
    case longBreak
}

final class PomodoroEngine: ObservableObject {
    weak var taskStore: TaskStore?

    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var completedWorkSessions: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var needsOvertimeConfirmation: Bool = false
    /// Denominator for work-phase progress (per-task countdown segment).
    @Published private(set) var workSegmentTotalSeconds: Int = 0

    private var timer: Timer?
    private var settings: PomodoroSettings
    /// Remaining seconds at the start of the current continuous work run (play → pause or complete).
    private var workSegmentBaselineRemaining: Int?
    /// Overtime elapsed seconds at the start of the current continuous overtime run.
    private var overtimeBaselineElapsed: Int?
    /// While in overtime, persist focused delta periodically so Obsidian stays up to date.
    private let overtimeAutosaveIntervalSeconds = 5

    var settingsSnapshot: PomodoroSettings {
        settings
    }

    /// Progress 0…1: elapsed share of the active task's full estimate (or default work length). Same while idle, paused, or running.
    var workSegmentProgress: Double {
        switch phase {
        case .work, .idle:
            let cap = taskStore?.focusBudgetCapForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            guard cap > 0 else { return 0 }
            let rem = max(0, remainingSeconds)
            return min(1, max(0, 1.0 - Double(rem) / Double(cap)))
        case .workOvertime:
            return 1
        case .shortBreak, .longBreak:
            return 0
        }
    }

    init(settings: PomodoroSettings = .default) {
        self.settings = settings
        remainingSeconds = settings.workSeconds
    }

    func updateSettings(_ new: PomodoroSettings) {
        settings = new
        guard !needsOvertimeConfirmation else { return }
        if timer == nil, phase == .idle || phase == .work {
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: new.workSeconds) ?? new.workSeconds
            remainingSeconds = max(0, budget)
        }
    }

    /// Syncs the displayed countdown from the active task (vault / saved remaining / estimate / default) whenever the timer is not running.
    func refreshRemainingFromActiveTask() {
        guard timer == nil, !needsOvertimeConfirmation else { return }
        switch phase {
        case .idle, .work:
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
        case .workOvertime, .shortBreak, .longBreak:
            break
        }
    }

    func startOrResume() {
        guard timer == nil else { return }
        if phase == .idle {
            phase = .work
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
            if remainingSeconds == 0 {
                needsOvertimeConfirmation = true
                return
            }
        }
        if phase == .workOvertime {
            startOvertimeTimer()
            return
        }
        if remainingSeconds <= 0 {
            finishCurrentPhase()
            return
        }
        startTimer()
    }

    func pause() {
        flushWorkSegmentToTaskStoreOnPause()
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentTotalSeconds = 0
    }

    /// After the user marks the active task done (floating card / elsewhere): flush timer, dismiss time-up sheet, idle, sync countdown from store.
    func syncAfterMarkingActiveTaskComplete() {
        pause()
        needsOvertimeConfirmation = false
        phase = .idle
        refreshRemainingFromActiveTask()
    }

    /// Flushes running work/overtime into `TaskStore` using the same rules as pause (remaining countdown + focused seconds), then stops the timer. Call before app termination so vault markdown matches the UI.
    func persistUncommittedStateBeforeTermination() {
        flushWorkSegmentToTaskStoreOnPause()
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentTotalSeconds = 0
    }

    func resetSession() {
        flushWorkSegmentToTaskStoreOnPause()
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentTotalSeconds = 0
        needsOvertimeConfirmation = false
        overtimeBaselineElapsed = nil
        phase = .idle
        completedWorkSessions = 0
        remainingSeconds = settings.workSeconds
    }

    /// Stops the timer and sets the work countdown back to the task estimate (or default work length), without logging the current segment as focus time.
    func resetActiveTaskCountdownToEstimate() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentBaselineRemaining = nil
        overtimeBaselineElapsed = nil
        workSegmentTotalSeconds = 0
        needsOvertimeConfirmation = false

        if let id = taskStore?.activeTaskId {
            taskStore?.resetTaskTimer(id: id, defaultWorkSeconds: settings.workSeconds)
        }

        switch phase {
        case .shortBreak, .longBreak:
            phase = .idle
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
        case .idle, .work, .workOvertime:
            phase = .idle
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
        }
    }

    func skipPhase() {
        flushWorkSegmentToTaskStoreOnPause()
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentTotalSeconds = 0
        needsOvertimeConfirmation = false
        overtimeBaselineElapsed = nil
        if phase == .workOvertime {
            phase = .work
        }
        advancePhase()
        if phase != .idle {
            startTimer()
        }
    }

    /// User confirmed they are still working after the timer reached zero.
    func continueOvertime() {
        guard needsOvertimeConfirmation else { return }
        needsOvertimeConfirmation = false
        phase = .workOvertime
        if timer == nil {
            startOvertimeTimer()
        }
    }

    /// User declined overtime after reaching zero; return to ready (breaks are disabled).
    func finishWorkAtLimit() {
        guard needsOvertimeConfirmation else { return }
        needsOvertimeConfirmation = false
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentTotalSeconds = 0
        overtimeBaselineElapsed = nil
        phase = .work
        advancePhase()
        if phase != .idle {
            startTimer()
        }
    }

    private func flushWorkSegmentToTaskStoreOnPause() {
        if phase == .work, let base = workSegmentBaselineRemaining {
            let consumed = max(0, base - remainingSeconds)
            taskStore?.commitFocusWorkPause(remainingWorkSeconds: remainingSeconds, addFocusedDeltaSeconds: consumed)
            workSegmentBaselineRemaining = nil
            return
        }
        if phase == .workOvertime, let base = overtimeBaselineElapsed {
            let consumed = max(0, remainingSeconds - base)
            taskStore?.commitFocusWorkPause(remainingWorkSeconds: 0, addFocusedDeltaSeconds: consumed)
            overtimeBaselineElapsed = nil
        }
    }

    private func startTimer() {
        timer?.invalidate()
        if phase == .work {
            workSegmentBaselineRemaining = remainingSeconds
            workSegmentTotalSeconds = remainingSeconds
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isRunning = true
    }

    private func startOvertimeTimer() {
        timer?.invalidate()
        overtimeBaselineElapsed = remainingSeconds
        workSegmentTotalSeconds = 0
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isRunning = true
    }

    private func tick() {
        if phase == .workOvertime {
            remainingSeconds += 1
            flushOvertimeAutosaveIfNeeded()
            return
        }
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
        if phase == .work, let base = workSegmentBaselineRemaining {
            let completedTaskId = taskStore?.activeTaskId
            taskStore?.commitFocusWorkPause(remainingWorkSeconds: 0, addFocusedDeltaSeconds: base)
            if let completedTaskId {
                taskStore?.markTaskCompleted(id: completedTaskId)
            }
            workSegmentBaselineRemaining = nil
            timer?.invalidate()
            timer = nil
            isRunning = false
            workSegmentTotalSeconds = 0
            remainingSeconds = 0
            needsOvertimeConfirmation = true
            return
        }
        timer?.invalidate()
        timer = nil
        isRunning = false
        workSegmentTotalSeconds = 0
        advancePhase()
        if phase != .idle {
            startTimer()
        }
    }

    private func flushOvertimeAutosaveIfNeeded() {
        guard phase == .workOvertime, let base = overtimeBaselineElapsed else { return }
        let delta = max(0, remainingSeconds - base)
        guard delta >= overtimeAutosaveIntervalSeconds else { return }
        taskStore?.commitFocusWorkPause(remainingWorkSeconds: 0, addFocusedDeltaSeconds: delta)
        overtimeBaselineElapsed = remainingSeconds
    }

    private func advancePhase() {
        switch phase {
        case .idle:
            phase = .work
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
        case .work, .workOvertime:
            completedWorkSessions += 1
            phase = .idle
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
        case .shortBreak, .longBreak:
            phase = .idle
            let budget = taskStore?.focusBudgetRemainingForActiveTask(defaultWorkSeconds: settings.workSeconds) ?? settings.workSeconds
            remainingSeconds = max(0, budget)
        }
    }
}
