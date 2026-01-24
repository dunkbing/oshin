import SwiftData
import SwiftUI

struct WorkspaceSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.order) private var workspaces: [Workspace]

    @Binding var selectedWorkspace: Workspace?
    @Binding var selectedRepository: Repository?

    @State private var showingAddRepository = false
    @State private var showingWorkspaceSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            workspaceSelector
            Divider()
            repositoryList.padding(.top, 5)
            Divider()
            footer
        }
    }

    private var workspaceSelector: some View {
        Button {
            showingWorkspaceSwitcher = true
        } label: {
            HStack {
                Circle()
                    .fill(Color(hex: selectedWorkspace?.colorHex ?? "#007AFF"))
                    .frame(width: 12, height: 12)

                Text(selectedWorkspace?.name ?? "Select Workspace")
                    .fontWeight(.medium)

                Spacer()

                Text("\(selectedWorkspace?.repositories.count ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingWorkspaceSwitcher) {
            WorkspaceSwitcherSheet(selectedWorkspace: $selectedWorkspace)
        }
    }

    @ViewBuilder
    private var repositoryList: some View {
        if let workspace = selectedWorkspace {
            if workspace.repositories.isEmpty {
                ContentUnavailableView(
                    "No Repositories",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a repository to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedRepository) {
                    ForEach(workspace.repositories) { repository in
                        RepositoryRowView(repository: repository)
                            .tag(repository)
                    }
                    .onDelete { indexSet in
                        deleteRepositories(at: indexSet, from: workspace)
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
            ContentUnavailableView(
                "No Workspace",
                systemImage: "square.stack.3d.up",
                description: Text("Select a workspace to view repositories.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showingAddRepository = true
            } label: {
                Label("Add Repository", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(selectedWorkspace == nil)

            Spacer()
        }
        .padding(12)
        .sheet(isPresented: $showingAddRepository) {
            if let workspace = selectedWorkspace {
                RepositoryAddSheet(workspace: workspace)
            }
        }
    }

    private func deleteRepositories(at offsets: IndexSet, from workspace: Workspace) {
        for index in offsets {
            let repository = workspace.repositories[index]
            if selectedRepository == repository {
                selectedRepository = nil
            }
            modelContext.delete(repository)
        }
    }
}

struct RepositoryRowView: View {
    let repository: Repository

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .lineLimit(1)

                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
