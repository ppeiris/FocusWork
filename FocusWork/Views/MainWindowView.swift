import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TaskListView()
                .environmentObject(model)
                .environmentObject(model.taskStore)
                .environmentObject(model.pomodoro)
                .tabItem { Label("Tasks", systemImage: "checklist") }

            SettingsView()
                .environmentObject(model)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            FloatingPanelController.shared.configureIfNeeded(model: model)
            model.applyFloatingWindowPreferences()
        }
    }
}
