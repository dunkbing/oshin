//
//  SettingsView.swift
//  oshin
//
//  Settings window with agent configuration
//

import SwiftUI
import os.log

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case general
    case agent(String)
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"

    @State private var selection: SettingsSelection? = .general
    @State private var agents: [AgentMetadata] = []
    @State private var showingAddCustomAgent = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gear")
                    .tag(SettingsSelection.general)

                Section("Agents") {
                    ForEach(agents, id: \.id) { agent in
                        HStack(spacing: 8) {
                            AgentIconView(iconType: agent.iconType, size: 20)
                            Text(agent.name)
                            Spacer()
                            if agent.id == defaultACPAgent {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .tag(SettingsSelection.agent(agent.id))
                        .contextMenu {
                            if agent.id != defaultACPAgent {
                                Button("Make Default") {
                                    defaultACPAgent = agent.id
                                }
                            }
                        }
                    }

                    Button {
                        showingAddCustomAgent = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                            Text("Add Custom Agent")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 750, minHeight: 500)
        .onAppear {
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadAgents()
        }
        .sheet(isPresented: $showingAddCustomAgent) {
            CustomAgentFormView(
                onSave: { _ in loadAgents() },
                onCancel: {}
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
                .navigationTitle("General")
        case .agent(let agentId):
            if let index = agents.firstIndex(where: { $0.id == agentId }) {
                AgentDetailView(
                    metadata: $agents[index],
                    isDefault: agentId == defaultACPAgent,
                    onSetDefault: { defaultACPAgent = agentId }
                )
                .id(agentId)
                .navigationTitle(agents[index].name)
                .navigationSubtitle("Agent Configuration")
            }
        case .none:
            GeneralSettingsView()
                .navigationTitle("General")
        }
    }

    private func loadAgents() {
        agents = AgentRegistry.shared.getAllAgents()
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 12

    var body: some View {
        Form {
            Section("Default Agent") {
                Picker("Default Agent", selection: $defaultACPAgent) {
                    ForEach(AgentRegistry.shared.getEnabledAgents(), id: \.id) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
            }

            Section("Diff View") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $diffFontSize, in: 10...18, step: 1) {
                        Text("Font Size")
                    }
                    .frame(width: 200)
                    Text("\(Int(diffFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Agent Icon View

struct AgentIconView: View {
    let iconType: AgentIconType
    let size: CGFloat

    var body: some View {
        Group {
            switch iconType {
            case .builtin(let name):
                builtinIcon(name)
            case .sfSymbol(let symbolName):
                Image(systemName: symbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .customImage(let data):
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    defaultIcon
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func builtinIcon(_ name: String) -> some View {
        switch name {
        case "claude":
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
        case "openai":
            Image(systemName: "brain")
                .foregroundStyle(.green)
        case "gemini":
            Image(systemName: "diamond")
                .foregroundStyle(.blue)
        case "droid":
            Image(systemName: "cpu")
                .foregroundStyle(.purple)
        case "kimi":
            Image(systemName: "k.circle.fill")
                .foregroundStyle(.pink)
        case "opencode":
            Image(systemName: "terminal")
                .foregroundStyle(.cyan)
        case "vibe":
            Image(systemName: "waveform")
                .foregroundStyle(.indigo)
        case "qwen":
            Image(systemName: "q.circle.fill")
                .foregroundStyle(.teal)
        default:
            defaultIcon
        }
    }

    private var defaultIcon: some View {
        Image(systemName: "cpu")
            .foregroundStyle(.secondary)
    }
}

// MARK: - Agent Detail View

struct AgentDetailView: View {
    @Binding var metadata: AgentMetadata
    let isDefault: Bool
    let onSetDefault: () -> Void

    @StateObject private var installState = AgentInstallState.shared
    @State private var isAgentValid = false
    @State private var showingFilePicker = false

    private var isInstalling: Bool {
        installState.isInstalling(metadata.id)
    }

    private var installError: String? {
        installState.getError(metadata.id)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AgentIconView(iconType: metadata.iconType, size: 32)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(metadata.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            if !metadata.isBuiltIn {
                                Text("Custom")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(4)
                            }
                        }

                        if let description = metadata.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { metadata.isEnabled },
                            set: { newValue in
                                metadata.isEnabled = newValue
                                Task {
                                    await AgentRegistry.shared.updateAgent(metadata)
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            if metadata.isEnabled {
                Section {
                    HStack {
                        Label {
                            Text(isDefault ? "This is the default agent" : "Set as default agent")
                        } icon: {
                            Circle()
                                .fill(isDefault ? .blue : .secondary.opacity(0.3))
                                .frame(width: 10, height: 10)
                        }

                        Spacer()

                        if !isDefault {
                            Button("Make Default") {
                                onSetDefault()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if metadata.canEditPath {
                    Section("Executable") {
                        HStack(spacing: 8) {
                            TextField(
                                "Path",
                                text: Binding(
                                    get: { metadata.executablePath ?? "" },
                                    set: { newValue in
                                        metadata.executablePath = newValue.isEmpty ? nil : newValue
                                        Task {
                                            await AgentRegistry.shared.updateAgent(metadata)
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("Browse...") {
                                showingFilePicker = true
                            }
                            .buttonStyle(.bordered)

                            if let path = metadata.executablePath, !path.isEmpty {
                                Image(systemName: isAgentValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(isAgentValid ? .green : .red)
                            }
                        }

                        if !metadata.launchArgs.isEmpty {
                            Text("Launch arguments: \(metadata.launchArgs.joined(separator: " "))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Section("Executable") {
                        HStack {
                            Text(metadata.executablePath ?? "Not installed")
                                .foregroundStyle(metadata.executablePath != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: isAgentValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isAgentValid ? .green : .red)
                        }

                        if !metadata.launchArgs.isEmpty {
                            Text("Launch arguments: \(metadata.launchArgs.joined(separator: " "))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Installation section for built-in agents
                    if metadata.installMethod != nil {
                        Section("Installation") {
                            if isInstalling {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Installing...")
                                        .foregroundStyle(.secondary)
                                }
                            } else if !isAgentValid {
                                Button {
                                    installAgent()
                                } label: {
                                    Label("Install agent", systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    updateAgent()
                                } label: {
                                    Label("Update Agent", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }

                            if let error = installError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.executable, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    metadata.executablePath = url.path
                    Task {
                        await AgentRegistry.shared.updateAgent(metadata)
                        validateAgent()
                    }
                }
            case .failure:
                break
            }
        }
        .task(id: metadata.executablePath) {
            validateAgent()
        }
    }

    private func validateAgent() {
        isAgentValid = AgentRegistry.shared.validateAgent(named: metadata.id)
    }

    private func installAgent() {
        let agentId = metadata.id
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.oshin",
            category: "AgentDetailView"
        )
        logger.info("Install button clicked for agent: \(agentId)")
        installState.setInstalling(agentId, true)

        Task {
            do {
                logger.info("Starting installation for \(agentId)...")
                try await AgentInstaller.shared.installAgent(metadata)
                logger.info("Installation completed for \(agentId)")
                await MainActor.run {
                    validateAgent()
                    installState.setInstalling(agentId, false)
                }
            } catch {
                logger.error("Installation failed for \(agentId): \(error.localizedDescription)")
                await MainActor.run {
                    installState.setError(agentId, error.localizedDescription)
                    installState.setInstalling(agentId, false)
                }
            }
        }
    }

    private func updateAgent() {
        let agentId = metadata.id
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.oshin",
            category: "AgentDetailView"
        )
        logger.info("Update button clicked for agent: \(agentId)")
        installState.setInstalling(agentId, true)

        Task {
            do {
                logger.info("Starting update for \(agentId)...")
                try await AgentInstaller.shared.updateAgent(metadata)
                logger.info("Update completed for \(agentId)")
                await MainActor.run {
                    validateAgent()
                    installState.setInstalling(agentId, false)
                }
            } catch {
                logger.error("Update failed for \(agentId): \(error.localizedDescription)")
                await MainActor.run {
                    installState.setError(agentId, error.localizedDescription)
                    installState.setInstalling(agentId, false)
                }
            }
        }
    }
}

// MARK: - Custom Agent Form View

struct CustomAgentFormView: View {
    let existingMetadata: AgentMetadata?
    let onSave: (AgentMetadata) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var executablePath: String = ""
    @State private var launchArgsString: String = ""
    @State private var showingFilePicker = false

    init(
        existingMetadata: AgentMetadata? = nil,
        onSave: @escaping (AgentMetadata) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingMetadata = existingMetadata
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Agent Info") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                }

                Section("Executable") {
                    HStack {
                        TextField("Path", text: $executablePath)
                        Button("Browse...") {
                            showingFilePicker = true
                        }
                    }
                    TextField("Launch Arguments (space-separated)", text: $launchArgsString)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveAgent()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || executablePath.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 350)
        .onAppear {
            if let metadata = existingMetadata {
                name = metadata.name
                description = metadata.description ?? ""
                executablePath = metadata.executablePath ?? ""
                launchArgsString = metadata.launchArgs.joined(separator: " ")
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.executable, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                executablePath = url.path
            }
        }
    }

    private func saveAgent() {
        let id = existingMetadata?.id ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
        let launchArgs =
            launchArgsString.isEmpty
            ? [] : launchArgsString.split(separator: " ").map(String.init)

        let metadata = AgentMetadata(
            id: id,
            name: name,
            description: description.isEmpty ? nil : description,
            iconType: existingMetadata?.iconType ?? .sfSymbol("cpu"),
            isBuiltIn: false,
            isEnabled: true,
            executablePath: executablePath,
            launchArgs: launchArgs
        )

        Task {
            await AgentRegistry.shared.addCustomAgent(metadata)
            onSave(metadata)
            dismiss()
        }
    }
}
