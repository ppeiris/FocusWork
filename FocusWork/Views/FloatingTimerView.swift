import SwiftUI

private struct FloatingPanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Extra height added to reported content when sizing the panel (shell insets beyond measured scroll content).
private let floatingPanelOuterVerticalMargin: CGFloat = 0

private let floatingPanelShellCornerRadius: CGFloat = 22

struct FloatingTimerView: View {
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var pomodoro: PomodoroEngine
    @State private var previewTaskId: UUID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: floatingPanelShellCornerRadius, style: .continuous)
                .fill(FloatingTimerPalette.shellFill)

            ScrollView {
                VStack(spacing: 0) {
                    if let active = tasks.activeTask,
                       let projectId = active.projectId,
                       let project = tasks.projects.first(where: { $0.id == projectId }) {
                        activeProjectSection(active: active, project: project, projectId: projectId)
                    } else {
                        VStack(spacing: 10) {
                            Text("No active task")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Press Start on a task in the list.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        }
                    }
                }
                .padding(6)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: FloatingPanelContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: floatingPanelShellCornerRadius, style: .continuous))
        .onPreferenceChange(FloatingPanelContentHeightKey.self) { height in
            #if os(macOS)
            FloatingPanelController.shared.applyReportedContentHeight(height + floatingPanelOuterVerticalMargin)
            #endif
        }
        .alert(
            "Time is up",
            isPresented: Binding(
                get: { pomodoro.needsOvertimeConfirmation },
                set: { _ in }
            )
        ) {
            Button("Yes, still working") {
                pomodoro.continueOvertime()
            }
            Button("No", role: .cancel) {
                pomodoro.finishWorkAtLimit()
            }
        } message: {
            Text("Are you still working on this task?")
        }
        .onChange(of: tasks.activeTaskId) { _, _ in
            if previewTaskId == tasks.activeTaskId {
                previewTaskId = nil
            }
        }
        .onChange(of: tasks.tasks.map(\.id)) { _, ids in
            if let previewTaskId, !ids.contains(previewTaskId) {
                self.previewTaskId = nil
            }
        }
    }

    /// Splits project tasks into rows above / below the active task (same order as the main list).
    private func floatingActiveQueueSplit(ordered: [FocusTask], activeId: UUID) -> (before: [FocusTask], after: [FocusTask]) {
        if let idx = ordered.firstIndex(where: { $0.id == activeId }) {
            return (Array(ordered.prefix(idx)), Array(ordered.dropFirst(idx + 1)))
        }
        return ([], ordered.filter { $0.id != activeId })
    }

    @ViewBuilder
    private func activeProjectSection(active: FocusTask, project: FocusProject, projectId: UUID) -> some View {
        let ordered = tasks.tasksOrderedInProject(projectId: projectId).filter { !$0.isCompleted }
        let defWork = pomodoro.settingsSnapshot.workSeconds

        VStack(spacing: 12) {
            if ordered.isEmpty {
                Text("No open tasks in this project")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                let split = floatingActiveQueueSplit(ordered: ordered, activeId: active.id)
                let beforeActive = split.before
                let afterActive = split.after

                if !beforeActive.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(beforeActive, id: \.id) { task in
                            floatingQueuedRow(task: task, defaultWorkSeconds: defWork)
                        }
                    }
                }

                if !active.isCompleted {
                    FloatingActiveTimerCard(
                        pomodoro: pomodoro,
                        projectName: project.name,
                        taskTitle: active.title,
                        taskNotes: active.notes,
                        liquidEmbedded: false
                    )
                }

                if !afterActive.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(afterActive, id: \.id) { task in
                            floatingQueuedRow(task: task, defaultWorkSeconds: defWork)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func floatingQueuedRow(task: FocusTask, defaultWorkSeconds: Int) -> some View {
        FloatingQueuedTaskRow(
            taskId: task.id,
            title: task.title,
            notes: task.notes,
            isCompleted: task.isCompleted,
            liquidEmbedded: false,
            isSelected: previewTaskId == task.id,
            timeSpendLine: queueTimeSpendLine(for: task),
            originalTimeText: originalTimeLabel(for: task),
            statusTimeText: statusTimeLabel(for: task),
            statusTimeColor: statusTimeColor(for: task)
        ) {
            previewTaskId = (previewTaskId == task.id) ? nil : task.id
        } onStartFocus: { taskId in
            previewTaskId = nil
            tasks.focusTask(id: taskId)
            pomodoro.startOrResume()
        } onResetTimer: { taskId in
            tasks.resetTaskTimer(id: taskId, defaultWorkSeconds: defaultWorkSeconds)
        }
    }

    /// Soft band between timer block and queue so the white mass feels continuous, not stacked boxes.
    private func liquidFlowDivider() -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0),
                            Color.primary.opacity(0.055),
                            Color.primary.opacity(0.08),
                            Color.primary.opacity(0.055),
                            Color.primary.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 14)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 10)
    }

    private func liquidRowSeparator() -> some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0),
                Color.primary.opacity(0.06),
                Color.primary.opacity(0.06),
                Color.primary.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func statusTimeLabel(for task: FocusTask) -> String {
        let defSec = pomodoro.settingsSnapshot.workSeconds
        if task.id == tasks.activeTaskId {
            switch pomodoro.phase {
            case .work:
                return "\(shortDuration(pomodoro.remainingSeconds)) left"
            case .workOvertime:
                return "+\(shortDuration(pomodoro.remainingSeconds)) overtime"
            default:
                break
            }
        }
        if task.isCompleted {
            return "Completed"
        }
        let left = tasks.focusRemainingSeconds(for: task, defaultWorkSeconds: defSec)
        if left > 0 {
            return "\(shortDuration(left)) left"
        }
        if let m = task.estimatedMinutes, m > 0 {
            let cap = m * 60
            let over = task.totalFocusedSeconds - cap
            if over > 0 {
                return "+\(shortDuration(over)) overtime"
            }
        }
        return "\(shortDuration(defSec)) left"
    }

    private func statusTimeColor(for task: FocusTask) -> Color {
        if task.id == tasks.activeTaskId, pomodoro.phase == .workOvertime { return .red }
        if task.isCompleted { return .secondary }
        let defSec = pomodoro.settingsSnapshot.workSeconds
        let left = tasks.focusRemainingSeconds(for: task, defaultWorkSeconds: defSec)
        if left == 0, let m = task.estimatedMinutes, m > 0, task.totalFocusedSeconds > m * 60 {
            return .red
        }
        return .primary
    }

    private func originalTimeLabel(for task: FocusTask) -> String {
        if let minutes = task.estimatedMinutes, minutes > 0 {
            return shortDuration(minutes * 60)
        }
        return shortDuration(pomodoro.settingsSnapshot.workSeconds)
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

    /// Second line on floating queue cards: `time spend: m:ss` (uses logged focus seconds).
    private func queueTimeSpendLine(for task: FocusTask) -> String {
        "time spend: \(shortDuration(task.totalFocusedSeconds))"
    }
}

// MARK: - Palette

private enum FloatingTimerPalette {
    static let cardFill = Color.white

    static let queueCardFill = Color(red: 0.96, green: 0.96, blue: 0.97)

    static let shellFill: Color = {
        #if os(macOS)
        Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.98)
        #else
        Color(uiColor: .systemGray6)
        #endif
    }()

    static let cardStroke = Color.black.opacity(0.06)
    static let shellStroke = Color.black.opacity(0.10)
    static let progressTrack = Color.black.opacity(0.08)
    static let progressBlue = Color(red: 0.30, green: 0.56, blue: 1.0)
    static let progressBlueEnd = Color(red: 0.50, green: 0.72, blue: 1.0)

    static let transportButtonRest = Color.black.opacity(0.05)
    static let transportButtonHover = Color.black.opacity(0.12)
    static let transportForeground = Color.primary
}

// MARK: - Notes popover (shared with task list)

enum TaskNotesPopoverMetrics {
    /// Fixed popover width so long notes wrap instead of stretching the window horizontally.
    static let width: CGFloat = 300
    static let horizontalPadding: CGFloat = 16
    static var textColumnWidth: CGFloat { width - horizontalPadding * 2 }
    static let scrollMaxHeight: CGFloat = 280
}

struct TaskNotesPopoverContent: View {
    let taskTitle: String
    let notes: String

    private var trimmed: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let w = TaskNotesPopoverMetrics.textColumnWidth
        VStack(alignment: .leading, spacing: 10) {
            Text(taskTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: w, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(width: w)

            ScrollView {
                Text(trimmed.isEmpty ? "No notes for this task." : notes)
                    .font(.callout)
                    .foregroundStyle(trimmed.isEmpty ? .tertiary : .secondary)
                    .multilineTextAlignment(.leading)
                    .frame(width: w, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: w, maxHeight: TaskNotesPopoverMetrics.scrollMaxHeight)
        }
        .padding(TaskNotesPopoverMetrics.horizontalPadding)
        .frame(width: TaskNotesPopoverMetrics.width, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Active card

private struct FloatingActiveTimerCard: View {
    @EnvironmentObject private var tasks: TaskStore
    @ObservedObject var pomodoro: PomodoroEngine
    let projectName: String
    let taskTitle: String
    let taskNotes: String
    var liquidEmbedded: Bool = false
    @State private var isResetButtonHovered = false
    @State private var isPlayButtonHovered = false
    @State private var isCompleteButtonHovered = false
    @State private var showNotesPopover = false

    private var taskIsCompleted: Bool {
        tasks.activeTask?.isCompleted == true
    }

    private var activeTaskPriority: FocusTaskPriority {
        tasks.activeTask?.priority ?? .later
    }

    private func cycleActiveTaskPriority() {
        guard let id = tasks.activeTaskId,
              let t = tasks.tasks.first(where: { $0.id == id }) else { return }
        let next: FocusTaskPriority
        switch t.priority {
        case .later: next = .urgent
        case .urgent: next = .next
        case .next: next = .later
        }
        tasks.setPriority(id: id, priority: next)
    }

    /// Logged focus already exceeds estimate (vault totals); show like list overtime when not in live overtime mode.
    private var shouldShowStaticOvertimeDisplay: Bool {
        guard !taskIsCompleted else { return false }
        guard !pomodoro.isRunning, !pomodoro.needsOvertimeConfirmation else { return false }
        guard pomodoro.phase == .idle || pomodoro.phase == .work else { return false }
        guard pomodoro.remainingSeconds == 0 else { return false }
        guard let t = tasks.activeTask, let m = t.estimatedMinutes, m > 0 else { return false }
        return t.totalFocusedSeconds > m * 60
    }

    private var staticOvertimeSeconds: Int {
        guard let t = tasks.activeTask, let m = t.estimatedMinutes, m > 0 else { return 0 }
        return max(0, t.totalFocusedSeconds - m * 60)
    }

    private var phaseLabel: String {
        if shouldShowStaticOvertimeDisplay { return "Overtime" }
        switch pomodoro.phase {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .workOvertime: return "Overtime"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    private var timeString: String {
        if taskIsCompleted {
            return "0:00"
        }
        if pomodoro.phase == .workOvertime {
            let s = max(0, pomodoro.remainingSeconds)
            let m = s / 60
            let r = s % 60
            return "+" + String(format: "%d:%02d", m, r)
        }
        if shouldShowStaticOvertimeDisplay {
            let s = staticOvertimeSeconds
            let m = s / 60
            let r = s % 60
            return "+" + String(format: "%d:%02d", m, r)
        }
        let s = max(0, pomodoro.remainingSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private var sessionProgress: Double {
        switch pomodoro.phase {
        case .work, .idle:
            return pomodoro.workSegmentProgress
        case .workOvertime:
            return 1
        case .shortBreak:
            let t = pomodoro.settingsSnapshot.shortBreakSeconds
            guard t > 0 else { return 0 }
            return 1.0 - Double(max(0, pomodoro.remainingSeconds)) / Double(t)
        case .longBreak:
            let t = pomodoro.settingsSnapshot.longBreakSeconds
            guard t > 0 else { return 0 }
            return 1.0 - Double(max(0, pomodoro.remainingSeconds)) / Double(t)
        }
    }

    private var progressTint: Color {
        switch pomodoro.phase {
        case .work, .workOvertime, .idle:
            return FloatingTimerPalette.progressBlue
        case .shortBreak, .longBreak:
            return Color.orange.opacity(0.88)
        }
    }

    private var showPhaseBanner: Bool {
        if taskIsCompleted { return false }
        return shouldShowStaticOvertimeDisplay
            || pomodoro.phase == .shortBreak
            || pomodoro.phase == .longBreak
            || pomodoro.phase == .idle
            || pomodoro.phase == .workOvertime
    }

    private var timerTextColor: Color {
        pomodoro.phase == .workOvertime || shouldShowStaticOvertimeDisplay ? .red : .primary
    }

    private var showEstimateResetButton: Bool {
        switch pomodoro.phase {
        case .idle, .work, .workOvertime: return true
        case .shortBreak, .longBreak: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(projectName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
            }

            if showPhaseBanner {
                Text(phaseLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phaseBannerColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(phaseBannerColor.opacity(0.15))
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(taskTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: cycleActiveTaskPriority) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(floatingBookmarkFillColor(for: activeTaskPriority))
                            .frame(minWidth: 22, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("Cycle priority (Later → Urgent → Next)")
                    #endif

                    Button {
                        showNotesPopover = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 22, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNotesPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        TaskNotesPopoverContent(taskTitle: taskTitle, notes: taskNotes)
                    }
                    #if os(macOS)
                    .help("Show task notes")
                    #endif

                    if taskIsCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(minWidth: 22, minHeight: 26)
                            .accessibilityLabel("Completed")
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Text(timeString)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timerTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(FloatingTimerPalette.progressTrack)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [progressTint, FloatingTimerPalette.progressBlueEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(min(1, sessionProgress))))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.25), value: sessionProgress)

            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .leading) {
                    if showEstimateResetButton {
                        Button {
                            pomodoro.resetActiveTaskCountdownToEstimate()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FloatingTimerPalette.transportForeground)
                                .frame(width: 40, height: 40)
                                .background {
                                    Circle()
                                        .fill(isResetButtonHovered ? FloatingTimerPalette.transportButtonHover : FloatingTimerPalette.transportButtonRest)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isResetButtonHovered)
                        #if os(macOS)
                        .onHover { isResetButtonHovered = $0 }
                        #endif
                        .accessibilityLabel("Reset timer to estimate")
                    }
                }
                .frame(width: 44, alignment: .leading)

                Spacer(minLength: 0)

                Button {
                    if pomodoro.isRunning {
                        pomodoro.pause()
                    } else {
                        pomodoro.startOrResume()
                    }
                } label: {
                    Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FloatingTimerPalette.transportForeground)
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(isPlayButtonHovered ? FloatingTimerPalette.transportButtonHover : FloatingTimerPalette.transportButtonRest)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isPlayButtonHovered)
                #if os(macOS)
                .onHover { isPlayButtonHovered = $0 }
                #endif
                .accessibilityLabel(pomodoro.isRunning ? "Pause" : "Play")
                .disabled(taskIsCompleted)
                .opacity(taskIsCompleted ? 0.38 : 1)

                Spacer(minLength: 0)

                ZStack(alignment: .trailing) {
                    if showEstimateResetButton {
                        Button {
                            guard let id = tasks.activeTaskId else { return }
                            pomodoro.pause()
                            tasks.markTaskCompleted(id: id)
                            pomodoro.syncAfterMarkingActiveTaskComplete()
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(FloatingTimerPalette.transportForeground)
                                .frame(width: 40, height: 40)
                                .background {
                                    Circle()
                                        .fill(isCompleteButtonHovered ? FloatingTimerPalette.transportButtonHover : FloatingTimerPalette.transportButtonRest)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isCompleteButtonHovered)
                        #if os(macOS)
                        .onHover { isCompleteButtonHovered = $0 }
                        #endif
                        .accessibilityLabel("Mark task complete")
                        .disabled(taskIsCompleted)
                        .opacity(taskIsCompleted ? 0.38 : 1)
                    }
                }
                .frame(width: 44, alignment: .trailing)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, liquidEmbedded ? 20 : 24)
        .padding(.bottom, liquidEmbedded ? 2 : 0)
        .frame(maxWidth: .infinity)
        .modifier(LiquidCardChrome(enabled: !liquidEmbedded))
        .contextMenu {
            Button("Skip phase") {
                pomodoro.skipPhase()
            }
            Button("Reset session") {
                pomodoro.resetSession()
            }
            if let id = tasks.activeTaskId, !taskIsCompleted {
                Button("Mark task complete") {
                    pomodoro.pause()
                    tasks.markTaskCompleted(id: id)
                    pomodoro.syncAfterMarkingActiveTaskComplete()
                }
            }
        }
    }

    private var phaseBannerColor: Color {
        if shouldShowStaticOvertimeDisplay { return .red }
        switch pomodoro.phase {
        case .idle: return .secondary
        case .workOvertime: return .red
        case .shortBreak, .longBreak: return .orange
        default: return .secondary
        }
    }
}

/// Own shadow/stroke only when not part of the unified liquid sheet.
private struct LiquidCardChrome: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                }
        } else {
            content
        }
    }
}

// MARK: - Priority bookmark (matches TaskListView)

fileprivate func floatingBookmarkFillColor(for priority: FocusTaskPriority) -> Color {
    switch priority {
    case .urgent:
        return .red
    case .next:
        return .blue
    case .later:
        return Color.gray.opacity(0.5)
    }
}

// MARK: - Queued task (outline pill on shared white)

private struct FloatingQueuedTaskRow: View {
    @EnvironmentObject private var tasks: TaskStore
    let taskId: UUID
    let title: String
    let notes: String
    var isCompleted: Bool = false
    var liquidEmbedded: Bool = false
    var isSelected: Bool = false
    /// Second line, e.g. `time spend: 0:26`.
    let timeSpendLine: String
    let originalTimeText: String
    let statusTimeText: String
    let statusTimeColor: Color
    let onSelect: () -> Void
    let onStartFocus: (UUID) -> Void
    let onResetTimer: (UUID) -> Void
    @State private var isQueuedPlayHovered = false
    @State private var isQueuedResetHovered = false
    @State private var showNotesPopover = false

    private var rowPriority: FocusTaskPriority {
        tasks.tasks.first(where: { $0.id == taskId })?.priority ?? .later
    }

    private func cycleQueuedPriority() {
        guard let t = tasks.tasks.first(where: { $0.id == taskId }) else { return }
        let next: FocusTaskPriority
        switch t.priority {
        case .later: next = .urgent
        case .urgent: next = .next
        case .next: next = .later
        }
        tasks.setPriority(id: taskId, priority: next)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isSelected ? 8 : 0) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(timeSpendLine)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Button(action: cycleQueuedPriority) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(floatingBookmarkFillColor(for: rowPriority))
                            .frame(minWidth: 20, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("Cycle priority (Later → Urgent → Next)")
                    #endif

                    Button {
                        showNotesPopover = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 20, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNotesPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        TaskNotesPopoverContent(taskTitle: title, notes: notes)
                    }
                    #if os(macOS)
                    .help("Show task notes")
                    #endif

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(minWidth: 20, minHeight: 26)
                            .accessibilityLabel("Completed")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, isSelected ? 0 : 12)

            if isSelected {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                HStack(alignment: .center, spacing: 10) {
                    Button(action: onSelect) {
                        HStack(spacing: 5) {
                            Text("est \(originalTimeText)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(statusTimeText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusTimeColor)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isCompleted {
                        Button {
                            onResetTimer(taskId)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FloatingTimerPalette.transportForeground)
                                .frame(width: 36, height: 36)
                                .background {
                                    Circle()
                                        .fill(isQueuedResetHovered ? FloatingTimerPalette.transportButtonHover : FloatingTimerPalette.transportButtonRest)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isQueuedResetHovered)
                        #if os(macOS)
                        .onHover { isQueuedResetHovered = $0 }
                        #endif
                        .accessibilityLabel("Reset task to redo")
                    } else {
                        Button {
                            onStartFocus(taskId)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FloatingTimerPalette.transportForeground)
                                .frame(width: 36, height: 36)
                                .background {
                                    Circle()
                                        .fill(isQueuedPlayHovered ? FloatingTimerPalette.transportButtonHover : FloatingTimerPalette.transportButtonRest)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isQueuedPlayHovered)
                        #if os(macOS)
                        .onHover { isQueuedPlayHovered = $0 }
                        #endif
                        .accessibilityLabel("Start this task")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background {
            Group {
                if liquidEmbedded {
                    Capsule(style: .continuous)
                        .fill(FloatingTimerPalette.queueCardFill)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(isSelected ? 0.06 : 0.03), radius: isSelected ? 6 : 3, x: 0, y: isSelected ? 3 : 1)
                }
            }
        }
        .overlay {
            if liquidEmbedded {
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(isSelected ? 0.10 : 0.05), lineWidth: 0.5)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(isSelected ? 0.10 : 0.05), lineWidth: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
