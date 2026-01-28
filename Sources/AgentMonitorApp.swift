import AppKit
import SwiftData
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Add atexit handler to catch unexpected terminations
        atexit {
            debugPrint("[DEBUG] atexit handler called - app is exiting!")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        debugPrint("[DEBUG] applicationShouldTerminateAfterLastWindowClosed called!")
        debugPrint("[DEBUG] Window count: \(NSApp.windows.count)")
        for (i, window) in NSApp.windows.enumerated() {
            debugPrint("[DEBUG] Window \(i): \(window), isVisible: \(window.isVisible), title: \(window.title)")
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugPrint("[DEBUG] applicationWillTerminate called!")
    }
}

@main
struct AgentMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            Repository.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])

            // Create default workspace if none exists
            Task { @MainActor in
                let context = container.mainContext
                let descriptor = FetchDescriptor<Workspace>()
                let workspaces = try? context.fetch(descriptor)

                if workspaces?.isEmpty ?? true {
                    let personalWorkspace = Workspace(name: "Personal", colorHex: "#007AFF", order: 0)
                    context.insert(personalWorkspace)
                }
            }

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
