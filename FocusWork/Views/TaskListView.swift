import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TaskListView: View {
    @EnvironmentObject private var tasks: TaskStore

    @State private var newTitle = ""
    @FocusState private var newFieldFocused: Bool
    @State private var showingNewTaskSheet = false
    @State private var draggingId: FocusTask.ID?
    @State private var orderedIds: [FocusTask.ID] = []
    @State private var hoverDestinationId: FocusTask.ID? = nil

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(.systemBackground)
            #endif

            ScrollView {
                VStack(spacing: 24) {
                    // Upcoming tasks timeline (titles only)
                    VStack(spacing: 16) {
                        // Plus card at the top
                        Button(action: { showingNewTaskSheet = true }) {
                            HStack { Spacer(); Image(systemName: "plus").font(.title3.weight(.semibold)); Spacer() }
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                                )
                        }
                        .buttonStyle(.plain)

                        ForEach(orderedTasks(), id: \.id) { task in
                            let isDragging = draggingId == task.id
                            let isAnotherDragging = draggingId != nil && draggingId != task.id

                            // If we're hovering over this task as a destination, show a placeholder slot above it
                            if hoverDestinationId == task.id {
                                PlaceholderRow()
                                    .contentShape(Rectangle())
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let sourceIdString = items.first, let sourceId = UUID(uuidString: sourceIdString) else { return false }
                                        // Commit directly to the hovered destination (this placeholder's row)
                                        let destination = task.id
                                        guard destination != sourceId else {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                                hoverDestinationId = nil
                                            }
                                            return true
                                        }
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                            reorderLocally(sourceId: sourceId, destinationId: destination)
                                            draggingId = nil
                                            hoverDestinationId = nil
                                        }
                                        return true
                                    } isTargeted: { hovering in
                                        if hovering {
                                            if hoverDestinationId != task.id {
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                                    hoverDestinationId = task.id
                                                }
                                            }
                                        } else {
                                            if hoverDestinationId == task.id {
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                                    hoverDestinationId = nil
                                                }
                                            }
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverDestinationId)
                            }

                            CreationRow(title: task.title, bookmarked: bookmarkColor(for: task))
                                .scaleEffect(isDragging ? 1.03 : 1.0)
                                .opacity(isAnotherDragging ? 0.96 : 1.0)
                                .shadow(color: isDragging ? .black.opacity(0.12) : .black.opacity(0.06), radius: isDragging ? 10 : 6, x: 0, y: isDragging ? 6 : 3)
                                .zIndex(isDragging ? 1 : 0)
                                .contentShape(Rectangle())
                                .onTapGesture { tasks.setActiveTask(id: task.id) }
                                .draggable(task.id.uuidString) {
                                    // Lifted preview while dragging
                                    CreationRow(title: task.title, bookmarked: bookmarkColor(for: task))
                                        .scaleEffect(1.05)
                                        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
                                }
                                .onDragBegan {
                                    draggingId = task.id
                                }
                                .onDragEnded { _ in
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                        hoverDestinationId = nil
                                        draggingId = nil
                                    }
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let sourceIdString = items.first, let sourceId = UUID(uuidString: sourceIdString) else { return false }
                                    // Prefer the hovered destination if available; otherwise fall back to this row's id
                                    let destination = hoverDestinationId ?? task.id
                                    // If destination equals source, do nothing but consume the drop
                                    guard destination != sourceId else {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                            hoverDestinationId = nil
                                        }
                                        return true
                                    }
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                        reorderLocally(sourceId: sourceId, destinationId: destination)
                                        draggingId = nil
                                        hoverDestinationId = nil
                                    }
                                    return true
                                } isTargeted: { hovering in
                                    if hovering {
                                        // Avoid targeting the same row we're dragging
                                        if draggingId == task.id { return }
                                        // Only update if this is a new target to prevent jitter
                                        if hoverDestinationId != task.id {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                                hoverDestinationId = task.id
                                            }
                                        }
                                    } else {
                                        // If we leave this row as a target, clear the placeholder if it was pointing here
                                        if hoverDestinationId == task.id {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                                hoverDestinationId = nil
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, draggingId == task.id ? 3 : 1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: orderedIds)
                    .animation(.easeInOut(duration: 0.15), value: draggingId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hoverDestinationId)
                }
                .padding(.vertical, 24)
            }
        }
        .tint(Color(red: 0.25, green: 0.55, blue: 0.95))
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskSheet(newTitle: $newTitle, onAdd: {
                addTask()
            })
            .presentationDetents([.medium])
        }
        .onAppear {
            orderedIds = tasks.tasks.map { $0.id }
        }
        .onChange(of: tasks.tasks.map { $0.id }) { newIds in
            // If tasks changed (added/removed), merge while preserving existing order
            let existingSet = Set(orderedIds)
            let newOnly = newIds.filter { !existingSet.contains($0) }
            // Remove ids that no longer exist
            orderedIds.removeAll { id in !newIds.contains(id) }
            orderedIds.append(contentsOf: newOnly)
        }
    }

    private func orderedTasks() -> [FocusTask] {
        let map = Dictionary(uniqueKeysWithValues: tasks.tasks.map { ($0.id, $0) })
        return orderedIds.compactMap { map[$0] }
    }

    private func bookmarkColor(for task: FocusTask) -> Color? {
        // Demo coloring: alternate colors; replace with real priority/flag when available
        if let idx = tasks.tasks.firstIndex(where: { $0.id == task.id }) {
            switch idx % 3 {
            case 0: return Color.red
            case 1: return Color.blue
            default: return nil // gray/disabled
            }
        }
        return nil
    }

    private func reorderLocally(sourceId: FocusTask.ID, destinationId: FocusTask.ID) {
        guard let from = orderedIds.firstIndex(of: sourceId), let to = orderedIds.firstIndex(of: destinationId) else { return }
        if from == to { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            var ids = orderedIds
            let element = ids.remove(at: from)
            ids.insert(element, at: to)
            orderedIds = ids
        }
    }

    private func addTask() {
        tasks.addTask(title: newTitle)
        // Attempt to append the most recently added id by diffing
        let currentIds = tasks.tasks.map { $0.id }
        if let newId = currentIds.first(where: { !orderedIds.contains($0) }) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                orderedIds.append(newId)
            }
        }
        newTitle = ""
        newFieldFocused = true
    }
}

private struct CreationRow: View {
    let title: String
    // When nil, show a gray bookmark; when non-nil, use the provided color
    let bookmarked: Color?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left")
                .foregroundStyle(.secondary)

            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "bookmark.fill")
                .foregroundStyle(bookmarked ?? Color.gray.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
    }
}

private struct PlaceholderRow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
                    .foregroundStyle(Color.gray.opacity(0.5))
            )
            .frame(height: 56)
            .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
            .padding(.horizontal, 0)
            .padding(.vertical, 2)
            .accessibilityLabel("Drop here")
            .accessibilityAddTraits(.isButton)
    }
}

private struct NewTaskSheet: View {
    @Binding var newTitle: String
    var onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("New task…", text: $newTitle)
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                        dismiss()
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension View {
    // A lightweight way to detect the start of a drag gesture using the drag preview phase
    func onDragBegan(_ action: @escaping () -> Void) -> some View {
        self.onAppear(perform: {}) // no-op to keep symmetry
            .onChange(of: DragAndDropPhase.current) { phase in
                if case .began = phase { action() }
            }
    }
    func onDragEnded(_ action: @escaping (Bool) -> Void) -> some View {
        self.onChange(of: DragAndDropPhase.current) { phase in
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

