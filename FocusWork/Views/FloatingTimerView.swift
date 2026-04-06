import SwiftUI

private struct FloatingPanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Matches vertical shell padding above and below the scroll content (`.padding(6)` × 2).
private let floatingPanelOuterVerticalMargin: CGFloat = 12

struct FloatingTimerView: View {
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var pomodoro: PomodoroEngine
    @State private var previewTaskId: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let active = tasks.activeTask,
                   let projectId = active.projectId,
                   let project = tasks.projects.first(where: { $0.id == projectId }) {
                    let ordered = tasks.tasksOrderedInProject(projectId: projectId)
                    let activeIndex = ordered.firstIndex(where: { $0.id == active.id }) ?? 0
                    let beforeActive = Array(ordered.prefix(activeIndex))
                    let afterActive = Array(ordered.dropFirst(activeIndex + 1))

                    VStack(spacing: 12) {
                        if !beforeActive.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(beforeActive, id: \.id) { task in
                                    FloatingQueuedTaskRow(
                                        taskId: task.id,
                                        title: task.title,
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
                                        tasks.resetTaskTimer(
                                            id: taskId,
                                            defaultWorkSeconds: pomodoro.settingsSnapshot.workSeconds
                                        )
                                    }
                                }
                            }
                        }

                        FloatingActiveTimerCard(
                            pomodoro: pomodoro,
                            projectName: project.name,
                            taskTitle: active.title,
                            liquidEmbedded: false
                        )

                        if !afterActive.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(afterActive, id: \.id) { task in
                                    FloatingQueuedTaskRow(
                                        taskId: task.id,
                                        title: task.title,
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
                                        tasks.resetTaskTimer(
                                            id: taskId,
                                            defaultWorkSeconds: pomodoro.settingsSnapshot.workSeconds
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        Text("No active task")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Press Start on a task in the list.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(FloatingTimerPalette.cardFill)
                            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 5)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(FloatingTimerPalette.cardStroke, lineWidth: 1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FloatingTimerPalette.shellFill)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(FloatingTimerPalette.shellStroke, lineWidth: 1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    static let cardFill: Color = {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }()

    static let queueCardFill: Color = {
        #if os(macOS)
        Color.white
        #else
        Color(uiColor: .systemBackground)
        #endif
    }()

    static let shellFill: Color = {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor).opacity(0.94)
        #else
        Color(uiColor: .systemGray6)
        #endif
    }()

    static let cardStroke = Color.primary.opacity(0.08)
    static let shellStroke = Color.primary.opacity(0.12)
    static let progressTrack = Color.gray.opacity(0.2)
    static let progressBlue = Color(red: 0.22, green: 0.52, blue: 0.96)
}

// MARK: - Active card

private struct FloatingActiveTimerCard: View {
    @EnvironmentObject private var tasks: TaskStore
    @ObservedObject var pomodoro: PomodoroEngine
    let projectName: String
    let taskTitle: String
    var liquidEmbedded: Bool = false
    @State private var isResetButtonHovered = false
    @State private var isPlayButtonHovered = false
    @State private var isCompleteButtonHovered = false

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
        VStack(alignment: .leading, spacing: 12) {
            Text(projectName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if showPhaseBanner {
                Text(phaseLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(phaseBannerColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(taskTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button(action: cycleActiveTaskPriority) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(floatingBookmarkFillColor(for: activeTaskPriority))
                            .frame(minWidth: 22, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("Cycle priority (Later → Urgent → Next)")
                    #endif

                    if taskIsCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(minWidth: 22, minHeight: 28)
                            .accessibilityLabel("Completed")
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Text(timeString)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timerTextColor)
                .frame(maxWidth: .infinity)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(FloatingTimerPalette.progressTrack)
                    Capsule()
                        .fill(progressTint)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, sessionProgress))))
                }
            }
            .frame(height: 10)
            .animation(.easeInOut(duration: 0.25), value: sessionProgress)

            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .leading) {
                    if showEstimateResetButton {
                        Button {
                            pomodoro.resetActiveTaskCountdownToEstimate()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(isResetButtonHovered ? Color.gray.opacity(0.28) : Color.clear)
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
                    Image(systemName: pomodoro.isRunning ? "pause" : "play")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(isPlayButtonHovered ? Color.gray.opacity(0.28) : Color.clear)
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
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(isCompleteButtonHovered ? Color.gray.opacity(0.28) : Color.clear)
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
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, liquidEmbedded ? 20 : 22)
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
                        .fill(FloatingTimerPalette.cardFill)
                        .shadow(color: .black.opacity(0.1), radius: 14, x: 0, y: 6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FloatingTimerPalette.cardStroke, lineWidth: 1)
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(timeSpendLine)
                            .font(.caption.weight(.medium))
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
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(floatingBookmarkFillColor(for: rowPriority))
                            .frame(minWidth: 22, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("Cycle priority (Later → Urgent → Next)")
                    #endif

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(minWidth: 22, minHeight: 28)
                            .accessibilityLabel("Completed")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, isSelected ? 0 : 12)

            if isSelected {
                Divider()
                    .padding(.horizontal, 18)
                HStack(alignment: .center, spacing: 10) {
                    Button(action: onSelect) {
                        HStack(spacing: 6) {
                            Text("est \(originalTimeText)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(statusTimeText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusTimeColor)
                        }
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isCompleted {
                        Button {
                            onResetTimer(taskId)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(isQueuedResetHovered ? Color.gray.opacity(0.28) : Color.clear)
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
                            Image(systemName: "play")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(isQueuedPlayHovered ? Color.gray.opacity(0.28) : Color.clear)
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
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .background {
            Group {
                if liquidEmbedded {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.06 : 0.025))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FloatingTimerPalette.queueCardFill)
                        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
                }
            }
        }
        .overlay {
            if liquidEmbedded {
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(isSelected ? 0.2 : 0.09), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(isSelected ? 0.22 : 0.12), lineWidth: 1.2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
