import Foundation
import Combine

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [FocusTask] = []
    @Published var activeTaskId: UUID?

    private let tasksKey = "focuswork.tasks"
    private let activeKey = "focuswork.activeTaskId"

    init() {
        load()
    }

    func addTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = FocusTask(title: trimmed)
        tasks.append(task)
        if activeTaskId == nil {
            activeTaskId = task.id
        }
        save()
    }

    func updateTask(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].title = trimmed
        save()
    }

    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        if activeTaskId == id {
            activeTaskId = tasks.first?.id
        }
        save()
    }

    func setActiveTask(id: UUID?) {
        guard id == nil || tasks.contains(where: { $0.id == id }) else { return }
        activeTaskId = id
        save()
    }

    var activeTask: FocusTask? {
        guard let id = activeTaskId else { return nil }
        return tasks.first { $0.id == id }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let decoded = try? JSONDecoder().decode([FocusTask].self, from: data) {
            tasks = decoded
        }
        if let s = UserDefaults.standard.string(forKey: activeKey), let u = UUID(uuidString: s) {
            activeTaskId = tasks.contains(where: { $0.id == u }) ? u : tasks.first?.id
        } else {
            activeTaskId = tasks.first?.id
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
        if let id = activeTaskId {
            UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }
}
