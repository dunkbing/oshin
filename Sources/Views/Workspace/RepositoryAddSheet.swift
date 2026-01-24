import SwiftUI
import SwiftData

enum AddRepositoryMode: String, CaseIterable {
    case existing = "Open Existing"
    case clone = "Clone"
    case create = "Create New"

    var icon: String {
        switch self {
        case .existing: return "folder"
        case .clone: return "arrow.down.circle"
        case .create: return "plus.square"
        }
    }
}

struct RepositoryAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let workspace: Workspace

    @State private var mode: AddRepositoryMode = .existing
    @State private var cloneURL = ""
    @State private var selectedPath = ""
    @State private var repositoryName = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Repository")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Mode picker
                    Picker("Mode", selection: $mode) {
                        ForEach(AddRepositoryMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.top)

                    switch mode {
                    case .existing:
                        existingView
                    case .clone:
                        cloneView
                    case .create:
                        createView
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(actionButtonText) {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 500)
        .frame(minHeight: 300, maxHeight: 450)
    }

    // MARK: - Existing Repository View

    private var existingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline)

            HStack {
                TextField("Select a folder...", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Choose...") {
                    selectExistingRepository()
                }
            }

            Text("Select a folder containing a Git repository.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !selectedPath.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectedPath)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Clone Repository View

    private var cloneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository URL")
                .font(.headline)

            TextField("https://github.com/user/repo.git", text: $cloneURL)
                .textFieldStyle(.roundedBorder)

            Text("Destination")
                .font(.headline)
                .padding(.top, 8)

            HStack {
                TextField("Select destination folder...", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Choose...") {
                    selectCloneDestination()
                }
            }

            Text("The repository will be cloned into a new folder at this location.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Create New Repository View

    private var createView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline)

            HStack {
                TextField("Select a folder...", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Choose...") {
                    selectNewRepositoryLocation()
                }
            }

            Text("Repository Name")
                .font(.headline)
                .padding(.top, 8)

            TextField("my-new-project", text: $repositoryName)
                .textFieldStyle(.roundedBorder)

            Text("A new Git repository will be initialized in a folder with this name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        switch mode {
        case .existing:
            return !selectedPath.isEmpty
        case .clone:
            return !cloneURL.isEmpty && !selectedPath.isEmpty
        case .create:
            return !selectedPath.isEmpty && !repositoryName.isEmpty
        }
    }

    private var actionButtonText: String {
        switch mode {
        case .existing: return "Add"
        case .clone: return "Clone"
        case .create: return "Create"
        }
    }

    // MARK: - Folder Selection

    private func selectExistingRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing a Git repository"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func selectCloneDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select where to clone the repository"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func selectNewRepositoryLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select where to create the new repository"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    // MARK: - Actions

    private func addRepository() {
        guard !isProcessing else { return }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let repoPath: String
                let repoName: String

                switch mode {
                case .existing:
                    repoPath = selectedPath
                    repoName = URL(fileURLWithPath: selectedPath).lastPathComponent

                case .clone:
                    repoName = extractRepoName(from: cloneURL)
                    repoPath = (selectedPath as NSString).appendingPathComponent(repoName)
                    try await cloneRepository(url: cloneURL, to: repoPath)

                case .create:
                    repoName = repositoryName
                    repoPath = (selectedPath as NSString).appendingPathComponent(repositoryName)
                    try await createRepository(at: repoPath)
                }

                await MainActor.run {
                    let repository = Repository(name: repoName, path: repoPath)
                    repository.workspace = workspace
                    modelContext.insert(repository)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func extractRepoName(from url: String) -> String {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(string: cleanURL)?.lastPathComponent ?? cleanURL
        return name.replacingOccurrences(of: ".git", with: "")
    }

    private func cloneRepository(url: String, to path: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", url, path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Clone failed"
            throw NSError(domain: "RepositoryAdd", code: 1, userInfo: [NSLocalizedDescriptionKey: errorString])
        }
    }

    private func createRepository(at path: String) async throws {
        // Create directory
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        // Initialize git repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Init failed"
            throw NSError(domain: "RepositoryAdd", code: 1, userInfo: [NSLocalizedDescriptionKey: errorString])
        }
    }
}
