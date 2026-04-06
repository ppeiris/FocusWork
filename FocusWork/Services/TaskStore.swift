import Foundation
import Combine

final class TaskStore: ObservableObject {
    @Published private(set) var projects: [FocusProject] = []
    @Published private(set) var tasks: [FocusTask] = []
    @Published var activeTaskId: UUID?
    /// When set, the main window shows the large focus card for this task (set by Start, cleared on other selection).
    @Published private(set) var pinnedFocusDisplayTaskId: UUID?
    @Published var selectedProjectId: UUID?
    @Published private(set) var vaultURL: URL?

    private let legacyProjectsKey = "focuswork.projects"
    private let legacyTasksKey = "focuswork.tasks"
    private let activeKey = "focuswork.activeTaskId"
    private let selectedProjectKey = "focuswork.selectedProjectId"
    private let vaultPathKey = "focuswork.obsidian.vaultPath"

    /// Invoked before `activeTaskId` changes so the focus timer can persist state for the outgoing task.
    var onWillChangeActiveTask: (() -> Void)?
    /// Invoked after `activeTaskId` changes so the focus UI can sync the countdown from the new task.
    var onDidChangeActiveTask: (() -> Void)?
    /// Invoked after tasks/projects are reloaded from disk or vault.
    var onDidReloadFromStorage: (() -> Void)?

    init() {
        if let path = UserDefaults.standard.string(forKey: vaultPathKey), !path.isEmpty {
            vaultURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        load()
    }

    func addProject(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let uniqueName = uniqueProjectName(from: trimmed)
        let project = FocusProject(name: uniqueName, sortOrder: projects.count)
        projects.append(project)
        selectedProjectId = project.id
        save()
    }

    func setSelectedProject(id: UUID?) {
        guard id == nil || projects.contains(where: { $0.id == id }) else { return }
        selectedProjectId = id
        saveSelectedProject()
    }

    func updateProject(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].name = trimmed
        save()
    }

    func setProjectCardColor(id: UUID, color: FocusProjectCardColor) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].cardColor = color
        save()
    }

    func reorderProjects(sourceId: UUID, destinationId: UUID) {
        guard let from = projects.firstIndex(where: { $0.id == sourceId }),
              let to = projects.firstIndex(where: { $0.id == destinationId }),
              from != to else { return }
        var reordered = projects
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        projects = reordered
        save()
    }

    func reorderProjectsToEnd(sourceId: UUID) {
        guard let from = projects.firstIndex(where: { $0.id == sourceId }) else { return }
        var reordered = projects
        let moved = reordered.remove(at: from)
        reordered.append(moved)
        projects = reordered
        save()
    }

    func addTask(title: String, estimatedMinutes: Int? = nil, projectId: UUID? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        ensureProjectExists()
        let targetProjectId = projectId ?? selectedProjectId ?? projects.first?.id
        let task = FocusTask(title: trimmed, projectId: targetProjectId, estimatedMinutes: normalizedEstimatedMinutes(estimatedMinutes))
        tasks.append(task)
        let firstActiveSelection = activeTaskId == nil
        if firstActiveSelection {
            activeTaskId = task.id
        }
        save()
        if firstActiveSelection {
            onDidChangeActiveTask?()
        }
    }

    func updateTask(id: UUID, title: String, estimatedMinutes: Int?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].title = trimmed
        tasks[i].estimatedMinutes = normalizedEstimatedMinutes(estimatedMinutes)
        tasks[i].isCompleted = false
        save()
    }

    func deleteTask(id: UUID) {
        let previousActive = activeTaskId
        if activeTaskId == id {
            onWillChangeActiveTask?()
        }
        tasks.removeAll { $0.id == id }
        if pinnedFocusDisplayTaskId == id {
            pinnedFocusDisplayTaskId = nil
        }
        if activeTaskId == id {
            activeTaskId = tasks.first?.id
        }
        save()
        if previousActive != activeTaskId {
            onDidChangeActiveTask?()
        }
    }

    func setPriority(id: UUID, priority: FocusTaskPriority) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].priority = priority
        save()
    }

    /// Resets a task's remaining work countdown back to its original estimate (or app default).
    func resetTaskTimer(id: UUID, defaultWorkSeconds: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let targetSeconds: Int
        if let estimate = tasks[i].estimatedMinutes, estimate > 0 {
            targetSeconds = estimate * 60
        } else {
            targetSeconds = max(1, defaultWorkSeconds)
        }
        tasks[i].savedWorkRemainingSeconds = targetSeconds
        tasks[i].isCompleted = false
        save()
    }

    func markTaskCompleted(id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isCompleted = true
        tasks[i].savedWorkRemainingSeconds = nil
        save()
    }

    /// Assigns a task to a project. List order is maintained by the UI (`orderedIdsByProject`).
    func moveTaskToProject(taskId: UUID, projectId: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        guard projects.contains(where: { $0.id == projectId }) else { return }
        tasks[i].projectId = projectId
        save()
    }

    /// Persists task order for a single project based on the provided ordered ids.
    /// Any project tasks not present in `orderedTaskIds` are appended in their current order.
    func setTaskOrder(projectId: UUID, orderedTaskIds: [UUID]) {
        let projectIndices = tasks.indices.filter { tasks[$0].projectId == projectId }
        guard !projectIndices.isEmpty else { return }

        let projectTasks = projectIndices.map { tasks[$0] }
        let byId = Dictionary(uniqueKeysWithValues: projectTasks.map { ($0.id, $0) })
        let ordered = orderedTaskIds.compactMap { byId[$0] }
        let remaining = projectTasks.filter { task in !orderedTaskIds.contains(task.id) }
        let finalProjectTasks = ordered + remaining
        guard finalProjectTasks.count == projectIndices.count else { return }

        for (offset, index) in projectIndices.enumerated() {
            tasks[index] = finalProjectTasks[offset]
        }
        save()
    }

    func setActiveTask(id: UUID?) {
        guard id == nil || tasks.contains(where: { $0.id == id }) else { return }
        let previous = activeTaskId
        if activeTaskId != id {
            onWillChangeActiveTask?()
        }
        pinnedFocusDisplayTaskId = nil
        activeTaskId = id
        saveActiveTask()
        if previous != activeTaskId {
            onDidChangeActiveTask?()
        }
    }

    /// Selects a task for focus: sets it active and moves its project to the top of the list (used by Start).
    func focusTask(id: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == id }) else { return }
        let previous = activeTaskId
        if activeTaskId != id {
            onWillChangeActiveTask?()
        }
        activeTaskId = id
        pinnedFocusDisplayTaskId = id
        var didReorder = false
        if let projectId = tasks[taskIndex].projectId,
           let from = projects.firstIndex(where: { $0.id == projectId }),
           from > 0 {
            var reordered = projects
            let moved = reordered.remove(at: from)
            reordered.insert(moved, at: 0)
            projects = reordered
            didReorder = true
        }
        if didReorder {
            save()
        } else {
            saveActiveTask()
        }
        if previous != activeTaskId {
            onDidChangeActiveTask?()
        }
    }

    var activeTask: FocusTask? {
        guard let id = activeTaskId else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Tasks for a project in master-list order (matches list/vault order for that project).
    func tasksOrderedInProject(projectId: UUID) -> [FocusTask] {
        tasks.filter { $0.projectId == projectId }
    }

    /// Full focus budget for the active task (estimate or default), used as the progress bar denominator.
    func focusBudgetCapForActiveTask(defaultWorkSeconds: Int) -> Int {
        guard let t = activeTask else { return defaultWorkSeconds }
        if let m = t.estimatedMinutes, m > 0 { return m * 60 }
        return defaultWorkSeconds
    }

    /// Remaining focus seconds for a task: mid-session save wins; else estimate (or default cap) minus logged `totalFocusedSeconds`, matching list row math.
    func focusRemainingSeconds(for task: FocusTask, defaultWorkSeconds: Int) -> Int {
        if task.isCompleted { return 0 }
        if let saved = task.savedWorkRemainingSeconds, saved > 0 { return saved }
        if let m = task.estimatedMinutes, m > 0 {
            return max(0, m * 60 - task.totalFocusedSeconds)
        }
        return defaultWorkSeconds
    }

    /// Work-phase countdown for the active task (same rules as `taskTimeLeftCaption` / vault semantics).
    func focusBudgetRemainingForActiveTask(defaultWorkSeconds: Int) -> Int {
        guard let t = activeTask else { return defaultWorkSeconds }
        return focusRemainingSeconds(for: t, defaultWorkSeconds: defaultWorkSeconds)
    }

    /// Persists paused work remaining and/or adds lapsed focus time (vault / UserDefaults).
    func commitFocusWorkPause(remainingWorkSeconds: Int, addFocusedDeltaSeconds: Int) {
        guard let id = activeTaskId, let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if addFocusedDeltaSeconds > 0 {
            tasks[i].totalFocusedSeconds += addFocusedDeltaSeconds
        }
        tasks[i].savedWorkRemainingSeconds = remainingWorkSeconds > 0 ? remainingWorkSeconds : nil
        save()
    }

    var projectsFolderURL: URL? {
        guard let vaultURL else { return nil }
        return vaultURL
            .appendingPathComponent("FocusWork", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
    }

    func configureVault(url: URL?) {
        vaultURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: vaultPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: vaultPathKey)
        }
        load()
    }

    func reloadFromStorage() {
        load()
    }

    /// Writes all projects/tasks to UserDefaults or the Obsidian vault (synchronous). Use on app quit after any in-memory timer flush.
    func persistAllToStorage() {
        save()
    }

    private func load() {
        if vaultURL != nil {
            loadFromVault()
        } else {
            loadFromLegacyDefaults()
        }

        ensureProjectExists()
        normalizeProjectOrder()
        normalizeTaskProjectLinks()
        restoreSelectionState()
        onDidReloadFromStorage?()
    }

    private func restoreSelectionState() {
        if let s = UserDefaults.standard.string(forKey: selectedProjectKey), let id = UUID(uuidString: s),
           projects.contains(where: { $0.id == id }) {
            selectedProjectId = id
        } else {
            selectedProjectId = projects.first?.id
        }

        if let s = UserDefaults.standard.string(forKey: activeKey), let id = UUID(uuidString: s),
           tasks.contains(where: { $0.id == id }) {
            activeTaskId = id
        } else {
            activeTaskId = tasks.first?.id
        }
    }

    private func save() {
        normalizeProjectOrder()
        if vaultURL != nil {
            saveToVault()
        } else {
            saveToLegacyDefaults()
        }
        saveSelectedProject()
        saveActiveTask()
    }

    private func saveSelectedProject() {
        if let id = selectedProjectId {
            UserDefaults.standard.set(id.uuidString, forKey: selectedProjectKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedProjectKey)
        }
    }

    private func saveActiveTask() {
        if let id = activeTaskId {
            UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }

    private func ensureProjectExists() {
        if projects.isEmpty {
            let inbox = FocusProject(name: "Project Name #1", sortOrder: 0)
            projects = [inbox]
            if selectedProjectId == nil {
                selectedProjectId = inbox.id
            }
        }
    }

    private func normalizeProjectOrder() {
        projects = projects.enumerated().map { index, project in
            var updated = project
            updated.sortOrder = index
            return updated
        }
    }

    private func normalizeTaskProjectLinks() {
        guard let fallbackProjectId = projects.first?.id else { return }
        for index in tasks.indices {
            if let currentId = tasks[index].projectId,
               projects.contains(where: { $0.id == currentId }) {
                continue
            }
            tasks[index].projectId = fallbackProjectId
        }
    }

    private func uniqueProjectName(from base: String) -> String {
        if !projects.contains(where: { $0.name.caseInsensitiveCompare(base) == .orderedSame }) {
            return base
        }
        var n = 2
        while true {
            let candidate = "\(base) \(n)"
            if !projects.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return candidate
            }
            n += 1
        }
    }

    private func loadFromLegacyDefaults() {
        if let projectData = UserDefaults.standard.data(forKey: legacyProjectsKey),
           let decodedProjects = try? JSONDecoder().decode([FocusProject].self, from: projectData) {
            projects = decodedProjects
        } else {
            projects = []
        }

        if let taskData = UserDefaults.standard.data(forKey: legacyTasksKey),
           let decodedTasks = try? JSONDecoder().decode([FocusTask].self, from: taskData) {
            tasks = decodedTasks
        } else {
            tasks = []
        }

        if projects.isEmpty, !tasks.isEmpty {
            let project = FocusProject(name: "Project Name #1", sortOrder: 0)
            projects = [project]
            for index in tasks.indices where tasks[index].projectId == nil {
                tasks[index].projectId = project.id
            }
        }
    }

    private func saveToLegacyDefaults() {
        if let projectData = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(projectData, forKey: legacyProjectsKey)
        }
        if let taskData = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(taskData, forKey: legacyTasksKey)
        }
    }

    private func loadFromVault() {
        guard let projectsFolderURL else {
            projects = []
            tasks = []
            return
        }

        do {
            let manager = FileManager.default
            try manager.createDirectory(at: projectsFolderURL, withIntermediateDirectories: true)

            let fileURLs = try manager.contentsOfDirectory(at: projectsFolderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent.hasPrefix("project_") }

            if !fileURLs.isEmpty {
                var loadedProjects: [FocusProject] = []
                var loadedTasks: [FocusTask] = []
                for fileURL in fileURLs {
                    let raw = try String(contentsOf: fileURL, encoding: .utf8)
                    let parsed = parseProjectFile(raw, fallbackFileName: fileURL.deletingPathExtension().lastPathComponent)
                    loadedProjects.append(parsed.project)
                    loadedTasks.append(contentsOf: parsed.tasks)
                }
                projects = loadedProjects.sorted {
                    if $0.sortOrder == $1.sortOrder {
                        return $0.createdAt < $1.createdAt
                    }
                    return $0.sortOrder < $1.sortOrder
                }
                tasks = loadedTasks
                return
            }

            let legacyProjectsFile = projectsFolderURL.deletingLastPathComponent().appendingPathComponent("Projects.md")
            if manager.fileExists(atPath: legacyProjectsFile.path) {
                let raw = try String(contentsOf: legacyProjectsFile, encoding: .utf8)
                let parsed = parseLegacyProjectsMarkdown(raw)
                projects = parsed.projects
                tasks = parsed.tasks
                saveToVault()
                return
            }

            let legacyTasksFile = projectsFolderURL.deletingLastPathComponent().appendingPathComponent("Tasks.md")
            if manager.fileExists(atPath: legacyTasksFile.path) {
                let raw = try String(contentsOf: legacyTasksFile, encoding: .utf8)
                tasks = parseLegacyTasksMarkdown(raw)
                let project = FocusProject(name: "Project Name #1", sortOrder: 0)
                projects = [project]
                for index in tasks.indices {
                    tasks[index].projectId = project.id
                }
                saveToVault()
                return
            }

            loadFromLegacyDefaults()
            if !projects.isEmpty || !tasks.isEmpty {
                saveToVault()
            }
        } catch {
            projects = []
            tasks = []
        }
    }

    private func saveToVault() {
        guard let projectsFolderURL else { return }

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: projectsFolderURL, withIntermediateDirectories: true)

            let fileNameMap = projectFileNameMap(for: projects)
            for project in projects {
                let projectTasks = tasks.filter { $0.projectId == project.id }
                let content = renderProjectFile(project: project, tasks: projectTasks)
                let fileURL = projectsFolderURL.appendingPathComponent(fileNameMap[project.id] ?? fileName(for: project))
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            let expected = Set(fileNameMap.values)
            let existing = try manager.contentsOfDirectory(at: projectsFolderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent.hasPrefix("project_") }

            for url in existing where !expected.contains(url.lastPathComponent) {
                try? manager.removeItem(at: url)
            }
        } catch {
            // Keep in-memory state on write failures.
        }
    }

    private func projectFileNameMap(for projects: [FocusProject]) -> [UUID: String] {
        var map: [UUID: String] = [:]
        var used: Set<String> = []

        for project in projects {
            let base = "project_\(sanitizedFileComponent(project.name))"
            var candidate = "\(base).md"
            if used.contains(candidate) {
                candidate = "\(base)_\(project.id.uuidString.prefix(8)).md"
            }
            used.insert(candidate)
            map[project.id] = candidate
        }

        return map
    }

    private func fileName(for project: FocusProject) -> String {
        "project_\(sanitizedFileComponent(project.name)).md"
    }

    private func sanitizedFileComponent(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let compact = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let scalars = compact.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "project" : result
    }

    private func parseProjectFile(_ text: String, fallbackFileName: String) -> (project: FocusProject, tasks: [FocusTask]) {
        var projectId: UUID?
        var projectName: String?
        var projectColor: FocusProjectCardColor = .gray
        var projectOrder: Int = 0
        var parsedTasks: [FocusTask] = []
        let lines = text.components(separatedBy: .newlines)

        var lineIndex = 0
        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("project_id:") {
                let raw = trimmed.replacingOccurrences(of: "project_id:", with: "").trimmingCharacters(in: .whitespaces)
                projectId = UUID(uuidString: raw)
                lineIndex += 1
                continue
            }
            if trimmed.hasPrefix("project_name:") {
                projectName = decodeText(trimmed.replacingOccurrences(of: "project_name:", with: "").trimmingCharacters(in: .whitespaces))
                lineIndex += 1
                continue
            }
            if trimmed.hasPrefix("project_color:") {
                let raw = trimmed.replacingOccurrences(of: "project_color:", with: "").trimmingCharacters(in: .whitespaces)
                projectColor = FocusProjectCardColor(rawValue: raw) ?? .gray
                lineIndex += 1
                continue
            }
            if trimmed.hasPrefix("project_order:") {
                let raw = trimmed.replacingOccurrences(of: "project_order:", with: "").trimmingCharacters(in: .whitespaces)
                projectOrder = Int(raw) ?? 0
                lineIndex += 1
                continue
            }
            if trimmed.hasPrefix("- [") {
                let (task, consumed) = parseTaskFromMarkdownLines(lines, startIndex: lineIndex, projectId: nil)
                if consumed > 0 {
                    parsedTasks.append(task)
                    lineIndex += consumed
                    continue
                }
            }
            lineIndex += 1
        }

        let id = projectId ?? UUID()
        let fallbackName = fallbackFileName
            .replacingOccurrences(of: "project_", with: "")
            .replacingOccurrences(of: "_", with: " ")
        let name = projectName ?? (fallbackName.isEmpty ? "Project" : fallbackName)
        let project = FocusProject(id: id, name: name, cardColor: projectColor, sortOrder: projectOrder)

        for index in parsedTasks.indices {
            parsedTasks[index].projectId = id
        }
        return (project, parsedTasks)
    }

    private func parseLegacyProjectsMarkdown(_ text: String) -> (projects: [FocusProject], tasks: [FocusTask]) {
        var parsedProjects: [FocusProject] = []
        var parsedTasks: [FocusTask] = []
        var currentProjectId: UUID?
        var projectIndex = 0

        let lines = text.components(separatedBy: .newlines)
        var lineIndex = 0
        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let header = String(trimmed.dropFirst(3))
                let parts = header.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let name = decodeText(parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "Project")
                let id = parts.count > 1 ? UUID(uuidString: String(parts[1]).trimmingCharacters(in: .whitespaces)) ?? UUID() : UUID()
                let project = FocusProject(id: id, name: name, sortOrder: projectIndex)
                parsedProjects.append(project)
                currentProjectId = project.id
                projectIndex += 1
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix("- ["), let projectId = currentProjectId {
                let (task, consumed) = parseTaskFromMarkdownLines(lines, startIndex: lineIndex, projectId: projectId)
                if consumed > 0 {
                    parsedTasks.append(task)
                    lineIndex += consumed
                    continue
                }
            }
            lineIndex += 1
        }

        return (parsedProjects, parsedTasks)
    }

    private func parseLegacyTasksMarkdown(_ text: String) -> [FocusTask] {
        var parsed: [FocusTask] = []
        let lines = text.components(separatedBy: .newlines)

        var lineIndex = 0
        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [") {
                let (task, consumed) = parseTaskFromMarkdownLines(lines, startIndex: lineIndex, projectId: nil)
                if consumed > 0 {
                    parsed.append(task)
                    lineIndex += consumed
                    continue
                }
            }
            lineIndex += 1
        }

        return parsed
    }

    private func renderProjectFile(project: FocusProject, tasks: [FocusTask]) -> String {
        var lines: [String] = [
            "# FocusWork Project",
            "project_name: \(encodeText(project.name))",
            "project_id: \(project.id.uuidString)",
            "project_color: \(project.cardColor.rawValue)",
            "project_order: \(project.sortOrder)",
            "",
            "<!-- Task: checkbox line then indented #fw/… tags (priority, id, title, est-min, work-rem-sec, total-focus-sec, completed). Legacy pipe lines still load. -->",
            ""
        ]

        for task in tasks {
            let mark = task.isCompleted ? "- [x]" : "- [ ]"
            lines.append("\(mark) ")
            lines.append("  #fw/priority \(task.priority.rawValue)")
            lines.append("  #fw/id \(task.id.uuidString)")
            lines.append("  #fw/title \(encodeFwTagLineValue(task.title))")
            if let m = task.estimatedMinutes {
                lines.append("  #fw/est-min \(m)")
            }
            if let rem = task.savedWorkRemainingSeconds, rem > 0 {
                lines.append("  #fw/work-rem-sec \(rem)")
            }
            lines.append("  #fw/total-focus-sec \(task.totalFocusedSeconds)")
            lines.append("  #fw/completed \(task.isCompleted ? "1" : "0")")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func encodeText(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    private func decodeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\|", with: "|")
    }

    /// Single-line value for `#fw/title` (and similar); newlines would break the tag row.
    private func encodeFwTagLineValue(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `- [ ]` / `- [x]` and the remainder of the first line (may be empty when using `#fw/…` lines below).
    private func parseTaskCheckboxLine(_ trimmed: String) -> (completed: Bool, body: String)? {
        if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
            let after = trimmed.dropFirst(5)
            return (true, after.trimmingCharacters(in: .whitespaces))
        }
        if trimmed.hasPrefix("- [ ]") {
            let after = trimmed.dropFirst(5)
            return (false, after.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Reads one task: legacy pipe line, title-only line, or checkbox + indented `#fw/key value` rows.
    private func parseTaskFromMarkdownLines(_ lines: [String], startIndex: Int, projectId: UUID?) -> (FocusTask, Int) {
        guard startIndex < lines.count else {
            return (FocusTask(title: "Untitled", priority: .later, projectId: projectId), 0)
        }
        let trimmed = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard let (checkboxDone, body) = parseTaskCheckboxLine(trimmed) else {
            return (FocusTask(title: "Untitled", priority: .later, projectId: projectId), 0)
        }

        if body.contains("|") {
            var t = taskFromMarkdownCheckboxBody(body, projectId: projectId)
            if checkboxDone { t.isCompleted = true }
            return (t, 1)
        }

        let bodyTrim = body.trimmingCharacters(in: .whitespaces)
        if !bodyTrim.isEmpty {
            let t = FocusTask(
                title: decodeText(bodyTrim),
                priority: .later,
                projectId: projectId,
                isCompleted: checkboxDone
            )
            return (t, 1)
        }

        var fields: [String: String] = [:]
        var j = startIndex + 1
        while j < lines.count {
            let rawLine = lines[j]
            if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                j += 1
                continue
            }
            let wsLength = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
            guard wsLength >= 1 else { break }
            let rest = String(rawLine.dropFirst(wsLength))
            guard rest.hasPrefix("#fw/") else { break }
            guard let spaceIdx = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                j += 1
                continue
            }
            let keyToken = String(rest[..<spaceIdx])
            guard keyToken.hasPrefix("#") else { break }
            let key = String(keyToken.dropFirst(1))
            let val = String(rest[rest.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = val
            j += 1
        }

        if fields.isEmpty {
            return (
                FocusTask(title: "", priority: .later, projectId: projectId, isCompleted: checkboxDone),
                1
            )
        }

        var t = focusTaskFromFwTagFields(fields, projectId: projectId)
        if checkboxDone { t.isCompleted = true }
        return (t, j - startIndex)
    }

    private func focusTaskFromFwTagFields(_ fields: [String: String], projectId: UUID?) -> FocusTask {
        let priorityRaw = fields["fw/priority"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let priority = FocusTaskPriority(rawValue: priorityRaw) ?? .later

        let idRaw = fields["fw/id"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let taskId = UUID(uuidString: idRaw) ?? UUID()

        let titleRaw = fields["fw/title"].map(decodeText) ?? ""
        let title = titleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "Untitled" : title

        let estMinutes = fields["fw/est-min"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { normalizedEstimatedMinutes($0) }
        let savedRem = fields["fw/work-rem-sec"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
        let totalLapsed = fields["fw/total-focus-sec"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 >= 0 ? $0 : nil } ?? 0

        let completedRaw = fields["fw/completed"]?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let completedFromTag = completedRaw == "1" || completedRaw == "true" || completedRaw == "yes"

        return FocusTask(
            id: taskId,
            title: displayTitle,
            priority: priority,
            projectId: projectId,
            estimatedMinutes: estMinutes,
            savedWorkRemainingSeconds: savedRem,
            totalFocusedSeconds: totalLapsed,
            isCompleted: completedFromTag
        )
    }

    private func normalizedEstimatedMinutes(_ minutes: Int?) -> Int? {
        guard let m = minutes, m > 0 else { return nil }
        return m
    }

    /// Parses legacy pipe-separated checkbox body: `priority | id | title [| est | work_rem | lapsed | completed]` (3–7 fields).
    private func taskFromMarkdownCheckboxBody(_ body: String, projectId: UUID? = nil) -> FocusTask {
        let parts = body.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false)
        guard parts.count >= 3 else {
            return FocusTask(title: decodeText(body), priority: .later, projectId: projectId)
        }

        let priorityRaw = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let idRaw = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let titleRaw = String(parts[2]).trimmingCharacters(in: .whitespaces)
        let priority = FocusTaskPriority(rawValue: priorityRaw) ?? .later
        let taskId = UUID(uuidString: idRaw) ?? UUID()

        let estMinutes: Int? = parts.count >= 4
            ? Int(String(parts[3]).trimmingCharacters(in: .whitespaces)).flatMap { normalizedEstimatedMinutes($0) }
            : nil
        let savedRem: Int? = parts.count >= 5
            ? Int(String(parts[4]).trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
            : nil
        let totalLapsed: Int = parts.count >= 6
            ? Int(String(parts[5]).trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil } ?? 0
            : 0
        let isCompleted: Bool = parts.count >= 7
            ? {
                let raw = String(parts[6]).trimmingCharacters(in: .whitespaces).lowercased()
                return raw == "1" || raw == "true" || raw == "yes"
            }()
            : false

        return FocusTask(
            id: taskId,
            title: decodeText(titleRaw),
            priority: priority,
            projectId: projectId,
            estimatedMinutes: estMinutes,
            savedWorkRemainingSeconds: savedRem,
            totalFocusedSeconds: totalLapsed,
            isCompleted: isCompleted
        )
    }
}
