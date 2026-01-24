import SwiftData
import SwiftUI

struct WorkspaceCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workspace.order) private var workspaces: [Workspace]

    @State private var name = ""
    @State private var selectedColor = "#007AFF"

    private let colors = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30",
        "#AF52DE", "#5856D6", "#FF2D55", "#00C7BE",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("New Workspace")
                    .font(.headline)

                Spacer()

                Button("Create") {
                    createWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Name", text: $name)

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 350, height: 280)
    }

    private func createWorkspace() {
        let maxOrder = workspaces.map(\.order).max() ?? 0
        let workspace = Workspace(
            name: name.trimmingCharacters(in: .whitespaces),
            colorHex: selectedColor,
            order: maxOrder + 1
        )
        modelContext.insert(workspace)
        dismiss()
    }
}
