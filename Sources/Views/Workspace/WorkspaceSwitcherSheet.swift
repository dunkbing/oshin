import SwiftUI
import SwiftData

struct WorkspaceSwitcherSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workspace.order) private var workspaces: [Workspace]

    @Binding var selectedWorkspace: Workspace?

    @State private var showingCreateWorkspace = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Switch Workspace")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Workspace List
            List(selection: $selectedWorkspace) {
                ForEach(workspaces) { workspace in
                    WorkspaceRowView(workspace: workspace)
                        .tag(workspace)
                        .onTapGesture {
                            selectedWorkspace = workspace
                            dismiss()
                        }
                }
                .onDelete(perform: deleteWorkspaces)
            }
            .listStyle(.plain)

            Divider()

            // Footer
            HStack {
                Button {
                    showingCreateWorkspace = true
                } label: {
                    Label("New Workspace", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding()
        }
        .frame(width: 350, height: 400)
        .sheet(isPresented: $showingCreateWorkspace) {
            WorkspaceCreateSheet()
        }
    }

    private func deleteWorkspaces(at offsets: IndexSet) {
        for index in offsets {
            let workspace = workspaces[index]
            // Don't delete if it's the only workspace
            if workspaces.count > 1 {
                if selectedWorkspace == workspace {
                    selectedWorkspace = workspaces.first { $0 != workspace }
                }
                modelContext.delete(workspace)
            }
        }
    }
}

struct WorkspaceRowView: View {
    let workspace: Workspace

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: workspace.colorHex))
                .frame(width: 12, height: 12)

            Text(workspace.name)

            Spacer()

            Text("\(workspace.repositories.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
