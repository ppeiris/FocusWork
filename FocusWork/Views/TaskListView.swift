import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var tasks: TaskStore

    @State private var newTitle = ""
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.title2.weight(.semibold))

            HStack {
                TextField("New task…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($newFieldFocused)
                    .onSubmit { addTask() }

                Button("Add") {
                    addTask()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            List {
                ForEach(tasks.tasks) { task in
                    TaskRow(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { tasks.setActiveTask(id: task.id) }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { tasks.tasks[$0].id }
                    ids.forEach { tasks.deleteTask(id: $0) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding()
    }

    private func addTask() {
        tasks.addTask(title: newTitle)
        newTitle = ""
        newFieldFocused = true
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var tasks: TaskStore
    let task: FocusTask

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack {
            if editing {
                TextField("Title", text: $draft, onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(task.title)
                    .lineLimit(2)
                Spacer()
                if tasks.activeTaskId == task.id {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(
            tasks.activeTaskId == task.id
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .contextMenu {
            Button("Rename") {
                draft = task.title
                editing = true
            }
            Button("Set active") {
                tasks.setActiveTask(id: task.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                tasks.deleteTask(id: task.id)
            }
        }
    }

    private func commit() {
        tasks.updateTask(id: task.id, title: draft)
        editing = false
    }
}
