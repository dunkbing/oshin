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
                        RepositoryRowView(repository: repository) {
                            deleteRepository(repository, from: workspace)
                        }
                        .tag(repository)
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

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .sheet(isPresented: $showingAddRepository) {
            if let workspace = selectedWorkspace {
                RepositoryAddSheet(workspace: workspace)
            }
        }
    }

    private func deleteRepository(_ repository: Repository, from workspace: Workspace) {
        if selectedRepository == repository {
            selectedRepository = nil
        }
        modelContext.delete(repository)
    }
}

struct RepositoryRowView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var appDetector = AppDetector.shared

    let repository: Repository
    var onDelete: (() -> Void)?

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
        .contextMenu {
            // Open in submenu
            Menu {
                // Terminals section
                let terminals = appDetector.getTerminals()
                if !terminals.isEmpty {
                    Section("Terminals") {
                        ForEach(terminals) { terminal in
                            Button {
                                appDetector.openPath(repository.path, with: terminal)
                            } label: {
                                AppMenuLabel(app: terminal)
                            }
                        }
                    }
                }

                // Editors section
                let editors = appDetector.getEditors()
                if !editors.isEmpty {
                    Section("Editors") {
                        ForEach(editors) { editor in
                            Button {
                                appDetector.openPath(repository.path, with: editor)
                            } label: {
                                AppMenuLabel(app: editor)
                            }
                        }
                    }
                }
            } label: {
                Label("Open in...", systemImage: "arrow.up.forward.app")
            }

            // Open in Finder
            Button {
                appDetector.openInFinder(repository.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            // Copy Path
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repository.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            Divider()

            // Remove Repository
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Remove Repository", systemImage: "trash")
            }
        }
    }
}

struct AppMenuLabel: View {
    let app: DetectedApp

    private func resizedIcon(_ image: NSImage, size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: resizedIcon(icon, size: CGSize(width: 16, height: 16)))
                    .renderingMode(.original)
            }
            Text(app.name)
        }
    }
}
