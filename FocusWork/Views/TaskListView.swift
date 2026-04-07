import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Dropdown values for task estimate: ∞, 5…120 minutes in steps of 5, or custom minutes.
private struct TaskEstimatePick: Hashable {
    enum Tag: Hashable {
        case infinity
        case preset(Int)
        case customEntry
    }

    var tag: Tag

    static let infinityPick = TaskEstimatePick(tag: .infinity)
    static let customPick = TaskEstimatePick(tag: .customEntry)
    /// Default selection when creating a new task.
    static let newTaskDefaultPick = TaskEstimatePick(tag: .preset(30))

    static var menuOptions: [TaskEstimatePick] {
        [TaskEstimatePick(tag: .infinity)]
            + stride(from: 5, through: 120, by: 5).map { TaskEstimatePick(tag: .preset($0)) }
            + [TaskEstimatePick(tag: .customEntry)]
    }

    /// Between 1h and 2h (exclusive of endpoints) uses clock style: 1:05, 1:10, … 1:55.
    static func displayLabel(minutes m: Int) -> String {
        if m == 60 { return "1 hour" }
        if m == 120 { return "2 hours" }
        if m > 60 && m < 120 {
            return String(format: "%d:%02d", m / 60, m % 60)
        }
        return "\(m) min"
    }

    var menuLabel: String {
        switch tag {
        case .infinity: return "∞ Infinity"
        case .preset(let m): return Self.displayLabel(minutes: m)
        case .customEntry: return "Custom…"
        }
    }

    static func resolveEstimatedMinutes(pick: TaskEstimatePick, customText: String) -> Int? {
        switch pick.tag {
        case .infinity: return nil
        case .preset(let m): return m
        case .customEntry:
            let t = customText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let n = Int(t), n > 0 else { return nil }
            return n
        }
    }

    /// If stored minutes match a preset row, use it; otherwise use Custom with the value as text.
    static func matching(stored minutes: Int?) -> (pick: TaskEstimatePick, customText: String) {
        guard let m = minutes, m > 0 else {
            return (.infinityPick, "")
        }
        if m % 5 == 0, (5...120).contains(m) {
            return (TaskEstimatePick(tag: .preset(m)), "")
        }
        return (.customPick, String(m))
    }
}

private struct TaskTimeSummaryLine {
    /// Localized “added” date (task creation / added to project).
    let addedLabel: String
    let original: String
    let elapsed: String
    let left: String
    let overtime: String?
}

struct TaskListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var pomodoro: PomodoroEngine

    @State private var newTitle = ""
    @State private var newTaskNotes = ""
    @State private var newTaskEstimatePick = TaskEstimatePick.newTaskDefaultPick
    @State private var newTaskCustomMinutesText = ""
    @State private var newProjectName = ""
    @FocusState private var newFieldFocused: Bool
    @State private var showingNewProjectSheet = false
    @State private var showingEditProjectSheet = false
    @State private var showingNewTaskSheet = false
    @State private var showingEditTaskSheet = false
    @State private var editingProjectId: FocusProject.ID?
    @State private var editProjectName = ""
    @State private var editingTaskId: FocusTask.ID?
    @State private var editTitle = ""
    @State private var editTaskNotes = ""
    @State private var editTaskEstimatePick = TaskEstimatePick.infinityPick
    @State private var editTaskCustomMinutesText = ""
    @State private var newTaskProjectId: FocusProject.ID?
    @State private var draggingId: FocusTask.ID?
    @State private var draggingProjectCardId: FocusProject.ID?
    @State private var draggingProjectId: FocusProject.ID?
    @State private var expandedProjectIds: Set<FocusProject.ID> = []
    @State private var hoverDestinationId: FocusTask.ID? = nil
    @State private var hoverProjectDestinationId: FocusProject.ID?
    /// Which project’s “drop at end of list” zone is active (nil if none).
    @State private var hoverTaskListEndProjectId: FocusProject.ID?
    @State private var hoverProjectListEnd = false
    /// Debounced clear when the pointer leaves row drop zones (`isTargeted(true)` cancels).
    @State private var hoverLeaveTask: Task<Void, Never>?
    @State private var hoverProjectLeaveTask: Task<Void, Never>?
    @State private var hoveredTaskId: FocusTask.ID?
    /// Project card highlighted while a task is dragged over it (move to project).
    @State private var hoverTaskOnProjectCardId: FocusProject.ID?

    @State private var isAddProjectHovered = false

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(.systemBackground)
            #endif

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Spacer()
                                Button(action: { showingNewProjectSheet = true }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                        .background {
                                            Circle()
                                                .fill(isAddProjectHovered ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                                        }
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .animation(.easeInOut(duration: 0.15), value: isAddProjectHovered)
                                #if os(macOS)
                                .onHover { isAddProjectHovered = $0 }
                                #endif
                                .accessibilityLabel("Create new project")
                            }

                            ForEach(tasks.projects) { project in
                            let isExpanded = expandedProjectIds.contains(project.id)
                            let isDraggingProject = draggingProjectCardId == project.id
                            let showProjectDropPlaceholder = hoverProjectDestinationId == project.id
                                && draggingProjectCardId != nil
                                && draggingProjectCardId != project.id

                            VStack(spacing: 12) {
                                if showProjectDropPlaceholder {
                                    PlaceholderRow()
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Button {
                                        toggleProjectExpansion(project.id)
                                    } label: {
                                        HStack(spacing: 0) {
                                            Text(project.name)
                                                .font(.headline.weight(.bold))
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            Spacer(minLength: 8)

                                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 24, height: 24)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isExpanded ? "Collapse project" : "Expand project")
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Menu {
                                        Button {
                                            startProject(project)
                                        } label: {
                                            Label("Start Project", systemImage: "play.circle.fill")
                                        }
                                        .disabled(orderedTasks(for: project.id).isEmpty)

                                        Button {
                                            endProject(project)
                                        } label: {
                                            Label("End Project", systemImage: "stop.circle")
                                        }

                                        Divider()

                                        Menu("Background Color") {
                                            ForEach(FocusProjectCardColor.allCases, id: \.self) { color in
                                                Button {
                                                    tasks.setProjectCardColor(id: project.id, color: color)
                                                } label: {
                                                    Text(projectColorMenuLabel(color))
                                                }
                                            }
                                        }

                                        Button {
                                            beginEditingProject(project)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 26, height: 26)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Project options")
                                }
                                .padding(.horizontal, TaskRowCardMetrics.horizontalPadding)
                                .padding(.vertical, isDraggingProject ? 3 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    if isDraggingProject {
                                        RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous)
                                            .fill(projectHeaderDragSourceFill())
                                    }
                                }
                                .overlay {
                                    if isDraggingProject {
                                        RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous)
                                            .stroke(Color.gray.opacity(0.35), lineWidth: 1.5)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous))
                                .opacity(isDraggingProject ? 0.5 : 1.0)
                                .animation(.easeInOut(duration: 0.15), value: isDraggingProject)
                                .draggable("project:\(project.id.uuidString)") {
                                    ProjectDragPreviewCard(
                                        title: project.name,
                                        isExpanded: isExpanded,
                                        cardBackground: projectBackgroundColor(project.cardColor)
                                    )
                                        .compositingGroup()
                                        .onAppear {
                                            draggingProjectCardId = project.id
                                        }
                                        .onDisappear {
                                            if draggingProjectCardId == project.id {
                                                cancelScheduledProjectHoverClear()
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                                    draggingProjectCardId = nil
                                                    hoverProjectDestinationId = nil
                                                    hoverProjectListEnd = false
                                                }
                                            }
                                        }
                                }
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 25)
                                        .onChanged { _ in
                                            draggingProjectCardId = project.id
                                        }
                                )
                                .onDragBegan {
                                    draggingProjectCardId = project.id
                                }
                                .onDragEnded { _ in
                                    cancelScheduledProjectHoverClear()
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                        hoverProjectDestinationId = nil
                                        hoverProjectListEnd = false
                                        draggingProjectCardId = nil
                                    }
                                }

                                if isExpanded {
                                        Button {
                                            newTaskProjectId = project.id
                                            newTitle = ""
                                            newTaskNotes = ""
                                            newTaskEstimatePick = .newTaskDefaultPick
                                            newTaskCustomMinutesText = ""
                                            showingNewTaskSheet = true
                                        } label: {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "plus")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                            }
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.white.opacity(0.7))
                                                    .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        ForEach(orderedTasks(for: project.id), id: \.id) { task in
                                            projectTaskRow(task: task, projectId: project.id)
                                        }

                                        if draggingId != nil, isExpanded {
                                            ZStack(alignment: .top) {
                                                Color.clear
                                                    .frame(height: 72)
                                                    .frame(maxWidth: .infinity)

                                                if hoverTaskListEndProjectId == project.id {
                                                    ListEndDropPlaceholderRow()
                                                        .padding(.top, 2)
                                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .dropDestination(for: String.self) { items, _ in
                                                guard let sourceIdString = items.first,
                                                      let sourceId = UUID(uuidString: sourceIdString),
                                                      tasks.tasks.contains(where: { $0.id == sourceId }) else { return false }
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                                    moveTask(sourceId: sourceId, toProject: project.id, beforeTaskId: nil)
                                                    draggingId = nil
                                                    draggingProjectId = nil
                                                    hoverDestinationId = nil
                                                    hoverTaskListEndProjectId = nil
                                                }
                                                return true
                                            } isTargeted: { hovering in
                                                if hovering {
                                                    cancelScheduledHoverClear()
                                                    hoverDestinationId = nil
                                                    if hoverTaskListEndProjectId != project.id {
                                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                                            hoverTaskListEndProjectId = project.id
                                                        }
                                                    }
                                                } else {
                                                    scheduleHoverLeaveClear()
                                                }
                                            }
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(projectBackgroundColor(project.cardColor))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        Color.accentColor.opacity(hoverTaskOnProjectCardId == project.id ? 0.40 : 0),
                                        lineWidth: 2
                                    )
                            }
                            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 3)
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .onTapGesture {
                                guard !isExpanded else { return }
                                toggleProjectExpansion(project.id)
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let payload = items.first else { return false }

                                if let sourceProjectId = parseProjectDragPayload(payload) {
                                    guard sourceProjectId != project.id else { return false }
                                    cancelScheduledProjectHoverClear()
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                        tasks.reorderProjects(sourceId: sourceProjectId, destinationId: project.id)
                                        draggingProjectCardId = nil
                                        hoverProjectDestinationId = nil
                                        hoverProjectListEnd = false
                                    }
                                    return true
                                }

                                if let taskId = UUID(uuidString: payload),
                                   tasks.tasks.contains(where: { $0.id == taskId }) {
                                    cancelScheduledProjectHoverClear()
                                    cancelScheduledHoverClear()
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                        moveTask(sourceId: taskId, toProject: project.id, beforeTaskId: nil)
                                        draggingId = nil
                                        draggingProjectId = nil
                                        hoverDestinationId = nil
                                        hoverTaskListEndProjectId = nil
                                        hoverTaskOnProjectCardId = nil
                                    }
                                    return true
                                }

                                return false
                            } isTargeted: { hovering in
                                if hovering {
                                    cancelScheduledProjectHoverClear()
                                    if draggingProjectCardId != nil {
                                        hoverProjectListEnd = false
                                        guard draggingProjectCardId != project.id else { return }
                                        if hoverProjectDestinationId != project.id {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                                hoverProjectDestinationId = project.id
                                            }
                                        }
                                    } else if draggingId != nil {
                                        hoverProjectDestinationId = nil
                                        hoverTaskListEndProjectId = nil
                                        if hoverTaskOnProjectCardId != project.id {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                                hoverTaskOnProjectCardId = project.id
                                            }
                                        }
                                    }
                                } else {
                                    if hoverTaskOnProjectCardId == project.id {
                                        hoverTaskOnProjectCardId = nil
                                    }
                                    scheduleProjectHoverLeaveClear()
                                }
                            }
                            }
                        }

                        if draggingProjectCardId != nil {
                            ZStack(alignment: .top) {
                                Color.clear
                                    .frame(height: 68)
                                    .frame(maxWidth: .infinity)
                                if hoverProjectListEnd {
                                    ListEndDropPlaceholderRow()
                                        .padding(.top, 2)
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in
                                guard let payload = items.first,
                                      let sourceId = parseProjectDragPayload(payload) else { return false }
                                cancelScheduledProjectHoverClear()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                    tasks.reorderProjectsToEnd(sourceId: sourceId)
                                    draggingProjectCardId = nil
                                    hoverProjectDestinationId = nil
                                    hoverProjectListEnd = false
                                }
                                return true
                            } isTargeted: { hovering in
                                if hovering {
                                    cancelScheduledProjectHoverClear()
                                    hoverProjectDestinationId = nil
                                    if !hoverProjectListEnd {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                            hoverProjectListEnd = true
                                        }
                                    }
                                } else {
                                    scheduleProjectHoverLeaveClear()
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: tasks.listOrderedTaskIdsByProject)
                    .animation(.easeInOut(duration: 0.15), value: draggingId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverDestinationId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverTaskListEndProjectId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverTaskOnProjectCardId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: tasks.projects.map(\.id))
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expandedProjectIds)
                    .animation(.easeInOut(duration: 0.15), value: draggingProjectCardId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverProjectDestinationId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverProjectListEnd)
                }
                .padding(.vertical, 24)
            }
            }

            #if os(macOS)
            MacDragOutsideClearMonitor(
                draggingId: $draggingId,
                hoverDestinationId: $hoverDestinationId,
                hoverTaskListEndProjectId: $hoverTaskListEndProjectId,
                draggingProjectCardId: $draggingProjectCardId,
                hoverProjectDestinationId: $hoverProjectDestinationId,
                hoverProjectListEnd: $hoverProjectListEnd
            )
            #endif
        }
        .tint(Color(red: 0.25, green: 0.55, blue: 0.95))
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet(newProjectName: $newProjectName, onAdd: {
                addProject()
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingEditProjectSheet) {
            EditProjectSheet(editProjectName: $editProjectName, onSave: {
                saveEditedProject()
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskSheet(
                newTitle: $newTitle,
                newNotes: $newTaskNotes,
                estimatePick: $newTaskEstimatePick,
                customMinutesText: $newTaskCustomMinutesText,
                onAdd: { addTaskToPendingProject() }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingEditTaskSheet) {
            EditTaskSheet(
                editTitle: $editTitle,
                editNotes: $editTaskNotes,
                estimatePick: $editTaskEstimatePick,
                customMinutesText: $editTaskCustomMinutesText,
                onSave: { saveEditedTask() }
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            tasks.reloadFromStorage()
            syncProjectOrders()
        }
        .onChange(of: tasks.tasks.map { $0.id }) { _, _ in
            syncProjectOrders()
        }
        .onChange(of: tasks.projects.map { $0.id }) { oldProjectIds, projectIds in
            syncProjectOrders()
            expandedProjectIds = expandedProjectIds.intersection(Set(projectIds))
            let oldSet = Set(oldProjectIds)
            // Do not auto-expand on first population (e.g. after launch); keep cards collapsed.
            guard !oldSet.isEmpty else { return }
            for projectId in projectIds where !oldSet.contains(projectId) && !expandedProjectIds.contains(projectId) {
                expandedProjectIds.insert(projectId)
            }
        }
        .onChange(of: draggingId) { _, newValue in
            if newValue == nil {
                cancelScheduledHoverClear()
                hoverTaskListEndProjectId = nil
                hoverTaskOnProjectCardId = nil
            }
        }
        .onChange(of: draggingProjectCardId) { _, newValue in
            if newValue == nil {
                cancelScheduledProjectHoverClear()
                hoverProjectDestinationId = nil
                hoverProjectListEnd = false
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tasks.reloadFromStorage()
        }
        #endif
    }

    private func cancelScheduledHoverClear() {
        hoverLeaveTask?.cancel()
        hoverLeaveTask = nil
    }

    /// Clears the gray slot shortly after the pointer is not over any row’s drop zone (any `isTargeted(true)` cancels this).
    private func scheduleHoverLeaveClear() {
        hoverLeaveTask?.cancel()
        hoverLeaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                hoverDestinationId = nil
                hoverTaskListEndProjectId = nil
            }
            hoverLeaveTask = nil
        }
    }

    private func cancelScheduledProjectHoverClear() {
        hoverProjectLeaveTask?.cancel()
        hoverProjectLeaveTask = nil
    }

    private func scheduleProjectHoverLeaveClear() {
        hoverProjectLeaveTask?.cancel()
        hoverProjectLeaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                hoverProjectDestinationId = nil
                hoverProjectListEnd = false
            }
            hoverProjectLeaveTask = nil
        }
    }

    private func projectHeaderDragSourceFill() -> Color {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor).opacity(0.28)
        #else
        Color.gray.opacity(0.28)
        #endif
    }

    private func orderedTasks(for projectId: FocusProject.ID) -> [FocusTask] {
        let projectTasks = tasksForProject(projectId)
        let map = Dictionary(uniqueKeysWithValues: projectTasks.map { ($0.id, $0) })
        let orderedIds = tasks.orderedTaskIds(for: projectId)
        return orderedIds.compactMap { map[$0] }
    }

    private func projectNameForActiveTask(_ task: FocusTask) -> String {
        guard let pid = task.projectId,
              let project = tasks.projects.first(where: { $0.id == pid }) else {
            return tasks.projects.first?.name ?? "Project"
        }
        return project.name
    }

    /// Remaining focus time for the row: live work countdown when this task is active, else saved segment, else estimate minus logged focus.
    private func taskTimeLeftCaption(for task: FocusTask) -> String? {
        if task.id == tasks.activeTaskId, pomodoro.phase == .work, pomodoro.remainingSeconds > 0 {
            return "\(Self.shortDurationLabel(forSeconds: pomodoro.remainingSeconds)) left"
        }
        if task.id == tasks.activeTaskId, pomodoro.phase == .workOvertime, pomodoro.remainingSeconds > 0 {
            return "+\(Self.shortDurationLabel(forSeconds: pomodoro.remainingSeconds))"
        }
        if let saved = task.savedWorkRemainingSeconds, saved > 0 {
            return "\(Self.shortDurationLabel(forSeconds: saved)) left"
        }
        if let m = task.estimatedMinutes, m > 0 {
            let estSec = m * 60
            let left = max(0, estSec - task.totalFocusedSeconds)
            if left > 0 {
                return "\(Self.shortDurationLabel(forSeconds: left)) left"
            }
        }
        return nil
    }

    private static func shortDurationLabel(forSeconds sec: Int) -> String {
        let s = max(0, sec)
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return r > 0 ? "\(m)m \(r)s" : "\(m)m" }
        return "\(r)s"
    }

    private static func compactClockLabel(forSeconds sec: Int) -> String {
        let s = max(0, sec)
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 {
            return String(format: "%d:%02d.%02d", h, m, r)
        }
        return String(format: "%d.%02d", m, r)
    }

    private func taskTimeSummary(for task: FocusTask) -> TaskTimeSummaryLine {
        let originalSeconds: Int = {
            if let m = task.estimatedMinutes, m > 0 {
                return m * 60
            }
            return pomodoro.settingsSnapshot.workSeconds
        }()

        let liveUncommittedElapsed: Int = {
            guard task.id == tasks.activeTaskId else { return 0 }
            switch pomodoro.phase {
            case .work:
                return max(0, pomodoro.workSegmentTotalSeconds - pomodoro.remainingSeconds)
            case .workOvertime, .idle, .shortBreak, .longBreak:
                return 0
            }
        }()

        let elapsedSeconds = max(0, task.totalFocusedSeconds + liveUncommittedElapsed)
        let leftSeconds = max(0, originalSeconds - elapsedSeconds)

        let overtimeSeconds: Int? = {
            let over = elapsedSeconds - originalSeconds
            return over > 0 ? over : nil
        }()

        return TaskTimeSummaryLine(
            addedLabel: Self.taskAddedDateLabel(for: task.createdAt),
            original: Self.compactClockLabel(forSeconds: originalSeconds),
            elapsed: Self.compactClockLabel(forSeconds: elapsedSeconds),
            left: Self.compactClockLabel(forSeconds: leftSeconds),
            overtime: overtimeSeconds.map { Self.compactClockLabel(forSeconds: $0) }
        )
    }

    private static func taskAddedDateLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(.autoupdatingCurrent))
    }

    @ViewBuilder
    private func projectTaskRow(task: FocusTask, projectId: FocusProject.ID) -> some View {
        let isDragging = draggingId == task.id
        let isDropTarget = hoverDestinationId == task.id
        let isPointerOverRow = hoveredTaskId == task.id
        let rowUsesLightGray = task.isCompleted || isPointerOverRow || isDragging || isDropTarget
        let rowIsElevated = isPointerOverRow && !isDragging && !task.isCompleted

        VStack(spacing: 16) {
            if hoverDestinationId == task.id {
                PlaceholderRow()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            CreationRow(
                title: task.title,
                notes: task.notes,
                estimatedMinutes: task.estimatedMinutes,
                totalFocusedSeconds: task.totalFocusedSeconds,
                timeLeftCaption: taskTimeLeftCaption(for: task),
                timeSummary: taskTimeSummary(for: task),
                isCompleted: task.isCompleted,
                bookmarked: bookmarkColor(for: task),
                usesLightGrayCard: rowUsesLightGray,
                isElevated: rowIsElevated,
                isBeingDragged: isDragging,
                onBookmarkTap: {
                    cycleTaskPriority(for: task)
                },
                onSetPriority: { priority in
                    tasks.setPriority(id: task.id, priority: priority)
                },
                onStart: {
                    tasks.focusTask(id: task.id)
                    expandedProjectIds.insert(projectId)
                    #if os(macOS)
                    FloatingPanelController.shared.configureIfNeeded(model: model)
                    #endif
                    pomodoro.startOrResume()
                },
                onEdit: {
                    beginEditing(task)
                },
                onReset: {
                    if tasks.activeTaskId == task.id {
                        pomodoro.resetSession()
                    }
                    tasks.resetTaskTimer(
                        id: task.id,
                        defaultWorkSeconds: pomodoro.settingsSnapshot.workSeconds
                    )
                },
                onDelete: {
                    deleteTask(task)
                }
            )
            .zIndex(isDragging ? 1 : 0)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredTaskId = task.id
                } else if hoveredTaskId == task.id {
                    hoveredTaskId = nil
                }
            }
            .draggable(task.id.uuidString) {
                CreationRow(title: task.title, bookmarked: bookmarkColor(for: task), usesLightGrayCard: true, showsMenu: false)
                    .compositingGroup()
                    .onAppear {
                        draggingId = task.id
                        draggingProjectId = projectId
                    }
                    .onDisappear {
                        if draggingId == task.id {
                            cancelScheduledHoverClear()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                hoverDestinationId = nil
                                hoverTaskListEndProjectId = nil
                                draggingId = nil
                                draggingProjectId = nil
                            }
                        }
                    }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onChanged { _ in
                        draggingId = task.id
                        draggingProjectId = projectId
                    }
            )
            .onDragBegan {
                draggingId = task.id
                draggingProjectId = projectId
            }
            .onDragEnded { _ in
                cancelScheduledHoverClear()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    hoverDestinationId = nil
                    hoverTaskListEndProjectId = nil
                    draggingId = nil
                    draggingProjectId = nil
                }
            }
            .padding(.vertical, isDragging ? 3 : 1)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let sourceIdString = items.first,
                  let sourceId = UUID(uuidString: sourceIdString),
                  tasks.tasks.contains(where: { $0.id == sourceId }) else { return false }
            let destination = task.id
            guard destination != sourceId else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    hoverDestinationId = nil
                    hoverTaskListEndProjectId = nil
                }
                return true
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                moveTask(sourceId: sourceId, toProject: projectId, beforeTaskId: destination)
                draggingId = nil
                draggingProjectId = nil
                hoverDestinationId = nil
                hoverTaskListEndProjectId = nil
            }
            return true
        } isTargeted: { hovering in
            if hovering {
                cancelScheduledHoverClear()
                hoverTaskListEndProjectId = nil
                guard draggingId != task.id else { return }
                if hoverDestinationId != task.id {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        hoverDestinationId = task.id
                    }
                }
            } else {
                scheduleHoverLeaveClear()
            }
        }
    }

    private func tasksForProject(_ projectId: FocusProject.ID) -> [FocusTask] {
        tasks.tasks.filter { $0.projectId == projectId }
    }

    private func startProject(_ project: FocusProject) {
        expandedProjectIds.insert(project.id)
        guard let firstOpen = orderedTasks(for: project.id).first(where: { !$0.isCompleted }) else {
            #if os(macOS)
            FloatingPanelController.shared.configureIfNeeded(model: model)
            #endif
            return
        }
        tasks.focusTask(id: firstOpen.id)
        #if os(macOS)
        FloatingPanelController.shared.configureIfNeeded(model: model)
        #endif
    }

    private func endProject(_ project: FocusProject) {
        guard let active = tasks.activeTask, active.projectId == project.id else { return }
        tasks.setActiveTask(id: nil)
    }

    private func taskProjectId(_ taskId: FocusTask.ID) -> FocusProject.ID? {
        tasks.tasks.first(where: { $0.id == taskId })?.projectId
    }

    private func syncProjectOrders() {
        tasks.syncListOrderWithTasks()
    }

    private func bookmarkColor(for task: FocusTask) -> Color? {
        switch task.priority {
        case .urgent:
            return Color.red
        case .next:
            return Color.blue
        case .later:
            return nil
        }
    }

    /// Cycles bookmark color / priority: Later → Urgent → Next → Later.
    private func cycleTaskPriority(for task: FocusTask) {
        let next: FocusTaskPriority
        switch task.priority {
        case .later: next = .urgent
        case .urgent: next = .next
        case .next: next = .later
        }
        tasks.setPriority(id: task.id, priority: next)
    }

    private func reorderLocally(sourceId: FocusTask.ID, destinationId: FocusTask.ID, projectId: FocusProject.ID) {
        var ids = tasks.orderedTaskIds(for: projectId)
        guard let from = ids.firstIndex(of: sourceId),
              let to = ids.firstIndex(of: destinationId) else { return }
        if from == to { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            let element = ids.remove(at: from)
            ids.insert(element, at: to)
            tasks.setListOrderedTaskIds(projectId: projectId, ids: ids)
        }
    }

    private func reorderLocallyToEnd(sourceId: FocusTask.ID, projectId: FocusProject.ID) {
        var ids = tasks.orderedTaskIds(for: projectId)
        guard let from = ids.firstIndex(of: sourceId) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            let element = ids.remove(at: from)
            ids.append(element)
            tasks.setListOrderedTaskIds(projectId: projectId, ids: ids)
        }
    }

    /// Reorders within a project or moves a task to another project. `beforeTaskId` nil means append at end.
    private func moveTask(sourceId: FocusTask.ID, toProject destinationProjectId: FocusProject.ID, beforeTaskId: FocusTask.ID?) {
        guard let sourceProjectId = taskProjectId(sourceId) else { return }

        if sourceProjectId == destinationProjectId {
            if let before = beforeTaskId, before != sourceId {
                reorderLocally(sourceId: sourceId, destinationId: before, projectId: destinationProjectId)
            } else {
                reorderLocallyToEnd(sourceId: sourceId, projectId: destinationProjectId)
            }
            let ordered = tasks.orderedTaskIds(for: destinationProjectId)
            tasks.setTaskOrder(projectId: destinationProjectId, orderedTaskIds: ordered)
            return
        }

        var sourceIds = tasks.orderedTaskIds(for: sourceProjectId)
        sourceIds.removeAll { $0 == sourceId }
        tasks.setListOrderedTaskIds(projectId: sourceProjectId, ids: sourceIds)

        var destIds = tasks.orderedTaskIds(for: destinationProjectId)
        destIds.removeAll { $0 == sourceId }

        tasks.moveTaskToProject(taskId: sourceId, projectId: destinationProjectId)

        if let before = beforeTaskId, before != sourceId, let idx = destIds.firstIndex(of: before) {
            destIds.insert(sourceId, at: idx)
        } else {
            destIds.append(sourceId)
        }
        tasks.setListOrderedTaskIds(projectId: destinationProjectId, ids: destIds)
        tasks.setTaskOrder(projectId: sourceProjectId, orderedTaskIds: tasks.orderedTaskIds(for: sourceProjectId))
        tasks.setTaskOrder(projectId: destinationProjectId, orderedTaskIds: destIds)
        syncProjectOrders()
    }

    private func addTaskToPendingProject() {
        guard let projectId = newTaskProjectId else { return }
        let minutes = TaskEstimatePick.resolveEstimatedMinutes(pick: newTaskEstimatePick, customText: newTaskCustomMinutesText)
        tasks.addTask(title: newTitle, estimatedMinutes: minutes, projectId: projectId, notes: newTaskNotes)
        syncProjectOrders()
        newTitle = ""
        newTaskNotes = ""
        newTaskEstimatePick = .newTaskDefaultPick
        newTaskCustomMinutesText = ""
        newTaskProjectId = nil
        newFieldFocused = true
    }

    private func addProject() {
        tasks.addProject(name: newProjectName)
        newProjectName = ""
        syncProjectOrders()
        if let newProjectId = tasks.projects.last?.id {
            expandedProjectIds.insert(newProjectId)
        }
    }

    private func beginEditingProject(_ project: FocusProject) {
        editingProjectId = project.id
        editProjectName = project.name
        showingEditProjectSheet = true
    }

    private func saveEditedProject() {
        guard let projectId = editingProjectId else { return }
        tasks.updateProject(id: projectId, name: editProjectName)
        showingEditProjectSheet = false
        editingProjectId = nil
        editProjectName = ""
    }

    private func beginEditing(_ task: FocusTask) {
        editingTaskId = task.id
        editTitle = task.title
        editTaskNotes = task.notes
        let matched = TaskEstimatePick.matching(stored: task.estimatedMinutes)
        editTaskEstimatePick = matched.pick
        editTaskCustomMinutesText = matched.customText
        showingEditTaskSheet = true
    }

    private func saveEditedTask() {
        guard let taskId = editingTaskId else { return }
        let minutes = TaskEstimatePick.resolveEstimatedMinutes(pick: editTaskEstimatePick, customText: editTaskCustomMinutesText)
        tasks.updateTask(id: taskId, title: editTitle, estimatedMinutes: minutes, notes: editTaskNotes)
        showingEditTaskSheet = false
        editingTaskId = nil
        editTitle = ""
        editTaskNotes = ""
        editTaskEstimatePick = .infinityPick
        editTaskCustomMinutesText = ""
    }

    private func deleteTask(_ task: FocusTask) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            tasks.deleteTask(id: task.id)
        }
    }

    private func projectColorName(_ color: FocusProjectCardColor) -> String {
        switch color {
        case .gray: return "Gray"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        }
    }

    private func projectColorMenuLabel(_ color: FocusProjectCardColor) -> String {
        switch color {
        case .gray: return "⚪ Gray"
        case .blue: return "🔵 Blue"
        case .green: return "🟢 Green"
        case .orange: return "🟠 Orange"
        case .pink: return "🩷 Pink"
        }
    }

    private func projectBackgroundColor(_ color: FocusProjectCardColor) -> Color {
        switch color {
        case .gray:
            return Color(red: 0.94, green: 0.94, blue: 0.95)
        case .blue:
            return Color(red: 0.90, green: 0.93, blue: 0.99)
        case .green:
            return Color(red: 0.90, green: 0.96, blue: 0.92)
        case .orange:
            return Color(red: 0.99, green: 0.94, blue: 0.90)
        case .pink:
            return Color(red: 0.98, green: 0.91, blue: 0.94)
        }
    }

    private func toggleProjectExpansion(_ projectId: FocusProject.ID) {
        if expandedProjectIds.contains(projectId) {
            expandedProjectIds.remove(projectId)
        } else {
            expandedProjectIds.insert(projectId)
        }
    }

    private func parseProjectDragPayload(_ payload: String) -> UUID? {
        guard payload.hasPrefix("project:") else { return nil }
        let raw = String(payload.dropFirst("project:".count))
        return UUID(uuidString: raw)
    }
}

#if os(macOS)
/// Clears reorder placeholder / drag state when the pointer leaves all app windows (SwiftUI often skips `isTargeted(false)` for an external drop).
private struct MacDragOutsideClearMonitor: View {
    @Binding var draggingId: FocusTask.ID?
    @Binding var hoverDestinationId: FocusTask.ID?
    @Binding var hoverTaskListEndProjectId: FocusProject.ID?
    @Binding var draggingProjectCardId: FocusProject.ID?
    @Binding var hoverProjectDestinationId: FocusProject.ID?
    @Binding var hoverProjectListEnd: Bool

    private var isActive: Bool {
        draggingId != nil || hoverDestinationId != nil || hoverTaskListEndProjectId != nil
            || draggingProjectCardId != nil || hoverProjectDestinationId != nil || hoverProjectListEnd
    }

    var body: some View {
        Group {
            if isActive {
                Color.clear
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                        guard draggingId != nil || hoverDestinationId != nil || hoverTaskListEndProjectId != nil
                            || draggingProjectCardId != nil || hoverProjectDestinationId != nil || hoverProjectListEnd else { return }
                        let mouse = NSEvent.mouseLocation
                        let insideAppWindow = NSApp.windows.contains { $0.isVisible && $0.frame.contains(mouse) }
                        if !insideAppWindow {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                draggingId = nil
                                hoverDestinationId = nil
                                hoverTaskListEndProjectId = nil
                                draggingProjectCardId = nil
                                hoverProjectDestinationId = nil
                                hoverProjectListEnd = false
                            }
                        }
                    }
            }
        }
    }
}
#endif

/// Pinned header for the active task: project name, title, pomodoro timer, session progress, and transport controls.
private struct ActiveFocusTaskCard: View {
    let projectName: String
    let taskTitle: String
    @ObservedObject var pomodoro: PomodoroEngine

    private var timeString: String {
        let s = max(0, pomodoro.remainingSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    /// Work uses per-task countdown; breaks use global pomodoro lengths.
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
            return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .shortBreak, .longBreak:
            return Color.orange.opacity(0.9)
        }
    }

    private var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(projectName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(taskTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(timeString)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.22))
                    Capsule()
                        .fill(progressTint)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, sessionProgress))))
                }
            }
            .frame(height: 10)
            .animation(.easeInOut(duration: 0.25), value: sessionProgress)

            HStack {
                Spacer(minLength: 0)
                Button {
                    if pomodoro.isRunning {
                        pomodoro.pause()
                    } else {
                        pomodoro.startOrResume()
                    }
                } label: {
                    Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pomodoro.isRunning ? "Pause" : "Play")
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contextMenu {
            Button("Skip phase") {
                pomodoro.skipPhase()
            }
            Button("Reset session") {
                pomodoro.resetSession()
            }
        }
    }
}

/// Shared metrics so list rows and the drag preview stay visually aligned.
private enum TaskRowCardMetrics {
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14
}

private struct CreationRow: View {
    let title: String
    var notes: String = ""
    var estimatedMinutes: Int? = nil
    var totalFocusedSeconds: Int = 0
    var timeLeftCaption: String? = nil
    var timeSummary: TaskTimeSummaryLine? = nil
    var isCompleted: Bool = false
    // When nil, show a gray bookmark; when non-nil, use the provided color
    let bookmarked: Color?
    /// Pointer hover, active drag, or drop target — slightly gray card instead of white.
    var usesLightGrayCard: Bool = false
    /// Pointer hover state to render a pop-out style card.
    var isElevated: Bool = false
    /// Source row visual while dragging this task.
    var isBeingDragged: Bool = false
    var showsMenu: Bool = true
    var onBookmarkTap: (() -> Void)? = nil
    var onSetPriority: ((FocusTaskPriority) -> Void)?
    var onStart: (() -> Void)? = nil
    var onEdit: (() -> Void)?
    var onReset: (() -> Void)? = nil
    var onDelete: (() -> Void)?

    private var cardFill: Color {
        if isBeingDragged {
            return Color.primary.opacity(0.06)
        }
        if usesLightGrayCard {
            #if os(macOS)
            return isElevated ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor)
            #else
            return isElevated ? Color(white: 0.94) : Color(white: 0.96)
            #endif
        }
        return Color.white
    }

    var body: some View {
        TaskRowCardContent(
            title: title,
            notes: notes,
            estimatedMinutes: estimatedMinutes,
            totalFocusedSeconds: totalFocusedSeconds,
            timeLeftCaption: timeLeftCaption,
            timeSummary: timeSummary,
            isCompleted: isCompleted,
            bookmarked: bookmarked,
            showsMenu: showsMenu,
            onBookmarkTap: onBookmarkTap,
            onSetPriority: onSetPriority,
            onStart: onStart,
            onEdit: onEdit,
            onReset: onReset,
            onDelete: onDelete
        )
            .padding(.horizontal, TaskRowCardMetrics.horizontalPadding)
            .padding(.vertical, TaskRowCardMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous)
                    .fill(cardFill)
                    .shadow(color: .black.opacity(isElevated ? 0.10 : 0.04), radius: isElevated ? 10 : 4, x: 0, y: isElevated ? 6 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous)
                    .stroke(
                        isBeingDragged ? Color.gray.opacity(0.30) : Color.primary.opacity(isElevated ? 0.08 : 0.04),
                        lineWidth: 0.5
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous))
            .scaleEffect(isElevated ? 1.015 : 1.0)
            .opacity(isBeingDragged ? 0.5 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: isElevated)
            .animation(.easeInOut(duration: 0.15), value: isBeingDragged)
            .animation(.easeInOut(duration: 0.18), value: usesLightGrayCard)
    }
}

private struct TaskRowCardContent: View {
    let title: String
    var notes: String = ""
    var estimatedMinutes: Int? = nil
    var totalFocusedSeconds: Int = 0
    var timeLeftCaption: String? = nil
    var timeSummary: TaskTimeSummaryLine? = nil
    var isCompleted: Bool = false
    let bookmarked: Color?
    var showsMenu: Bool = true
    var onBookmarkTap: (() -> Void)? = nil
    var onSetPriority: ((FocusTaskPriority) -> Void)?
    var onStart: (() -> Void)? = nil
    var onEdit: (() -> Void)?
    var onReset: (() -> Void)? = nil
    var onDelete: (() -> Void)?
    @State private var showsActionsPopover = false
    @State private var showNotesPopover = false

    private static func focusDurationLabel(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }

    private var notesPreview: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extra space between notes and the time row so the two blocks read as separate.
    private var timeRowTopInset: CGFloat {
        guard !notesPreview.isEmpty else { return 0 }
        if timeSummary != nil { return 10 }
        if let m = estimatedMinutes, m > 0 { return 10 }
        if timeLeftCaption != nil { return 10 }
        if totalFocusedSeconds > 0 { return 10 }
        return 0
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !notesPreview.isEmpty {
                    Button {
                        showNotesPopover = true
                    } label: {
                        Text(notesPreview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNotesPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        TaskNotesPopoverContent(taskTitle: title, notes: notes)
                    }
                    #if os(macOS)
                    .help("Show full notes")
                    #endif
                }
                Group {
                    if let summary = timeSummary {
                        (Text("added \(summary.addedLabel) · est: \(summary.original) · time elapsed: \(summary.elapsed) · time left: \(summary.left)")
                            .foregroundStyle(.secondary)
                         + Text(summary.overtime.map { " · over time +\($0)" } ?? "")
                            .foregroundStyle(.red))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    } else {
                        if let m = estimatedMinutes, m > 0 {
                            Text("Est. \(TaskEstimatePick.displayLabel(minutes: m))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let timeLeftCaption {
                            Text(timeLeftCaption)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if totalFocusedSeconds > 0 {
                            Text("Focused \(Self.focusDurationLabel(totalFocusedSeconds))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, timeRowTopInset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Completed")
                }
            }
            .frame(width: 24, height: 28, alignment: .center)
            .accessibilityHidden(!isCompleted)

            Group {
                if let onBookmarkTap {
                    Button {
                        onBookmarkTap()
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(bookmarked ?? Color.gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Cycle priority (Later → Urgent → Next)")
                } else {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(bookmarked ?? Color.gray.opacity(0.5))
                }
            }
            .frame(minWidth: 22, minHeight: 28)
            .contentShape(Rectangle())

            if showsMenu {
                Button {
                    showsActionsPopover.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsActionsPopover, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .trailing) {
                    VStack(spacing: 0) {
                        actionButton(title: "Urgent", systemImage: "bookmark.fill", iconColor: .red) {
                            onSetPriority?(.urgent)
                        }
                        actionButton(title: "Next", systemImage: "bookmark.fill", iconColor: .blue) {
                            onSetPriority?(.next)
                        }
                        actionButton(title: "Later", systemImage: "bookmark.fill", iconColor: .gray) {
                            onSetPriority?(.later)
                        }

                        Divider()

                        if onStart != nil {
                            actionButton(title: "Start", systemImage: "play.circle.fill", iconColor: .green) {
                                onStart?()
                            }
                        }

                        actionButton(title: "Reset", systemImage: "arrow.counterclockwise.circle", iconColor: .orange) {
                            onReset?()
                        }

                        actionButton(title: "Edit", systemImage: "pencil", iconColor: .blue) {
                            onEdit?()
                        }
                        actionButton(title: "Delete", systemImage: "trash", iconColor: .blue) {
                            onDelete?()
                        }
                    }
                    .frame(width: 144)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            showsActionsPopover = false
        } label: {
            ActionRowLabel(title: title, systemImage: systemImage, iconColor: iconColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ActionRowLabel: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
            Text(title)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct PlaceholderRow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.accentColor.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6]))
                    .foregroundStyle(Color.accentColor.opacity(0.30))
            )
            .frame(height: 52)
            .padding(.horizontal, 0)
            .padding(.vertical, 2)
            .accessibilityLabel("Drop here")
            .accessibilityAddTraits(.isButton)
    }
}

private struct ProjectDragPreviewCard: View {
    let title: String
    var isExpanded: Bool
    /// Matches the tinted project card on the list (same as `projectBackgroundColor`).
    var cardBackground: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, TaskRowCardMetrics.horizontalPadding)
        .padding(.vertical, TaskRowCardMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous)
                .fill(cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: TaskRowCardMetrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        .frame(minWidth: 280)
    }
}

/// Dashed slot shown under the list while reordering; pointer over the zone draws a subtle accent ring.
private struct ListEndDropPlaceholderRow: View {
    var body: some View {
        PlaceholderRow()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drop at end of list")
            .accessibilityAddTraits(.isButton)
    }
}

private struct NewTaskSheet: View {
    @Binding var newTitle: String
    @Binding var newNotes: String
    @Binding var estimatePick: TaskEstimatePick
    @Binding var customMinutesText: String
    var onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFieldFocused: Bool

    private var isCustomEstimate: Bool {
        if case .customEntry = estimatePick.tag { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Task")
                .font(.title3.weight(.semibold))

            TextField("What do you need to focus on?", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($titleFieldFocused)
                .onSubmit {
                    addAndDismiss()
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline.weight(.medium))
                Text("Saved in your Obsidian project file; not shown in the floating timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $newNotes)
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Estimated time to complete")
                    .font(.subheadline.weight(.medium))
                Picker("Estimated time to complete", selection: $estimatePick) {
                    ForEach(TaskEstimatePick.menuOptions, id: \.self) { pick in
                        Text(pick.menuLabel).tag(pick)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if isCustomEstimate {
                    TextField("Minutes", text: $customMinutesText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    addAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
        .onAppear {
            titleFieldFocused = true
        }
    }

    private func addAndDismiss() {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAdd()
        dismiss()
    }
}

private struct NewProjectSheet: View {
    @Binding var newProjectName: String
    var onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title3.weight(.semibold))

            TextField("Project name…", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onSubmit {
                    addAndDismiss()
                }

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    addAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .onAppear {
            nameFieldFocused = true
        }
    }

    private func addAndDismiss() {
        guard !newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAdd()
        dismiss()
    }
}

private struct EditProjectSheet: View {
    @Binding var editProjectName: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project")
                .font(.title3.weight(.semibold))

            TextField("Project name…", text: $editProjectName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onSubmit {
                    saveAndDismiss()
                }

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .onAppear {
            nameFieldFocused = true
        }
    }

    private func saveAndDismiss() {
        guard !editProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave()
        dismiss()
    }
}

private struct EditTaskSheet: View {
    @Binding var editTitle: String
    @Binding var editNotes: String
    @Binding var estimatePick: TaskEstimatePick
    @Binding var customMinutesText: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFieldFocused: Bool

    private var isCustomEstimate: Bool {
        if case .customEntry = estimatePick.tag { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Task")
                .font(.title3.weight(.semibold))

            TextField("Task title…", text: $editTitle)
                .textFieldStyle(.roundedBorder)
                .focused($titleFieldFocused)
                .onSubmit {
                    saveAndDismiss()
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline.weight(.medium))
                Text("Saved in your Obsidian project file; not shown in the floating timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $editNotes)
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Estimated time to complete")
                    .font(.subheadline.weight(.medium))
                Picker("Estimated time to complete", selection: $estimatePick) {
                    ForEach(TaskEstimatePick.menuOptions, id: \.self) { pick in
                        Text(pick.menuLabel).tag(pick)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if isCustomEstimate {
                    TextField("Minutes", text: $customMinutesText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
        .onAppear {
            titleFieldFocused = true
        }
    }

    private func saveAndDismiss() {
        guard !editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave()
        dismiss()
    }
}

private extension View {
    // A lightweight way to detect the start of a drag gesture using the drag preview phase
    func onDragBegan(_ action: @escaping () -> Void) -> some View {
        self.onAppear(perform: {}) // no-op to keep symmetry
            .onChange(of: DragAndDropPhase.current) { _, phase in
                if case .began = phase { action() }
            }
    }
    func onDragEnded(_ action: @escaping (Bool) -> Void) -> some View {
        self.onChange(of: DragAndDropPhase.current) { _, phase in
            if case .ended = phase { action(true) }
        }
    }
}

// Minimal phase tracker for drag/drop using PreferenceKey
private enum DragAndDropPhase: Equatable {
    case idle
    case began
    case ended

    static var current: DragAndDropPhase { _Storage.shared.phase }

    fileprivate final class _Storage {
        static let shared = _Storage()
        var phase: DragAndDropPhase = .idle
    }
}
