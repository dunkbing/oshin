import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.order) private var workspaces: [Workspace]

    @State private var selectedWorkspace: Workspace?
    @State private var selectedRepository: Repository?

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebarView(
                selectedWorkspace: $selectedWorkspace,
                selectedRepository: $selectedRepository
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            if let repository = selectedRepository {
                RepositoryDetailView(repository: repository)
            } else {
                ContentUnavailableView(
                    "No Repository Selected",
                    systemImage: "folder",
                    description: Text("Select a repository from the sidebar or add a new one.")
                )
            }
        }
        .onAppear {
            if selectedWorkspace == nil {
                selectedWorkspace = workspaces.first
            }
        }
        .onChange(of: workspaces) { _, newValue in
            if selectedWorkspace == nil {
                selectedWorkspace = newValue.first
            }
        }
    }
}

struct RepositoryDetailView: View {
    let repository: Repository

    var body: some View {
        VStack {
            Text(repository.name)
                .font(.largeTitle)
            Text(repository.path)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
