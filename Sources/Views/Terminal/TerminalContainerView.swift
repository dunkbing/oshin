//
//  TerminalContainerView.swift
//  oshin
//

import SwiftUI

// MARK: - Terminal Tab View

struct TerminalTabView: View {
    let workingDirectory: String
    @ObservedObject var ghosttyApp: Ghostty.App

    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @State private var selectedSessionId: UUID?

    private var sessions: [TerminalSession] {
        sessionManager.getSessions(for: workingDirectory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TerminalTabBar(
                sessions: sessions,
                selectedSessionId: $selectedSessionId,
                onClose: { session in
                    closeSession(session)
                },
                onAdd: {
                    createNewSession()
                }
            )

            Divider()

            // Terminal content
            if sessions.isEmpty {
                terminalEmptyState
            } else {
                ZStack {
                    ForEach(sessions) { session in
                        let isSelected = selectedSessionId == session.id
                        TerminalPaneView(
                            session: session,
                            ghosttyApp: ghosttyApp,
                            sessionManager: sessionManager,
                            isSelected: isSelected,
                            onClose: {
                                closeSession(session)
                            }
                        )
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .zIndex(isSelected ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if sessions.isEmpty {
                createNewSession()
            } else if selectedSessionId == nil {
                selectedSessionId = sessions.first?.id
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Terminal Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Terminal")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createNewSession() {
        let session = sessionManager.createSession(for: workingDirectory)
        selectedSessionId = session.id
    }

    private func closeSession(_ session: TerminalSession) {
        let wasSelected = selectedSessionId == session.id
        sessionManager.removeSession(session)

        if wasSelected {
            selectedSessionId = sessions.first?.id
        }
    }
}

// MARK: - Terminal Tab Bar

struct TerminalTabBar: View {
    let sessions: [TerminalSession]
    @Binding var selectedSessionId: UUID?
    let onClose: (TerminalSession) -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(sessions) { session in
                        TerminalTabButton(
                            session: session,
                            isSelected: selectedSessionId == session.id,
                            onSelect: { selectedSessionId = session.id },
                            onClose: { onClose(session) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // New tab button
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Terminal Tab Button

struct TerminalTabButton: View {
    @ObservedObject var session: TerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Close button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)

                Image(systemName: "terminal")
                    .font(.system(size: 11))

                Text(session.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 100)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(session.title)
    }
}

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var ghosttyApp: Ghostty.App
    let sessionManager: TerminalSessionManager
    let isSelected: Bool
    let onClose: () -> Void

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0
    @State private var isResizing: Bool = false
    @State private var terminalSize: (columns: UInt16, rows: UInt16) = (0, 0)
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TerminalViewWrapper(
                    session: session,
                    ghosttyApp: ghosttyApp,
                    sessionManager: sessionManager,
                    onProcessExit: {
                        onClose()
                    },
                    onTitleChange: { title in
                        session.title = title
                    },
                    shouldFocus: shouldFocus,
                    isFocused: isSelected,
                    focusVersion: focusVersion,
                    size: geo.size
                )

                // Resize overlay
                if isResizing {
                    ResizeOverlay(columns: terminalSize.columns, rows: terminalSize.rows)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.1), value: isResizing)
                }
            }
            .onChange(of: geo.size) { _, _ in
                handleSizeChange()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    focusVersion += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
        }
        .onAppear {
            if isSelected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
        }
        .onDisappear {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        }
    }

    private func handleSizeChange() {
        guard let terminal = sessionManager.getTerminal(for: session.id),
            let termSize = terminal.terminalSize()
        else { return }

        terminalSize = (termSize.columns, termSize.rows)
        isResizing = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isResizing = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}

// MARK: - Resize Overlay

struct ResizeOverlay: View {
    let columns: UInt16
    let rows: UInt16

    var body: some View {
        Text("\(columns) × \(rows)")
            .font(.system(size: 24, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
