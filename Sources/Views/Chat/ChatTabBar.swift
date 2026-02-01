//
//  ChatTabBar.swift
//  oshin
//

import SwiftUI

// MARK: - Chat Tab Bar

struct ChatTabBar: View {
    let sessions: [ChatSession]
    @Binding var selectedSessionId: UUID?
    @Binding var showingAgentPicker: Bool
    @Binding var showingSidebar: Bool
    let onClose: (ChatSession) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .foregroundStyle(showingSidebar ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .help(showingSidebar ? "Hide sidebar" : "Show sidebar")

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(sessions) { session in
                        ChatTabButton(
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

            // New tab button with popover
            Button {
                showingAgentPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .popover(isPresented: $showingAgentPicker, arrowEdge: .bottom) {
                AgentPickerPopover { agentId in
                    onSelect(agentId)
                    showingAgentPicker = false
                }
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Chat Tab Button

struct ChatTabButton: View {
    @ObservedObject var session: ChatSession
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

                // Agent icon
                if let metadata = AgentRegistry.shared.getMetadata(for: session.agentId) {
                    AgentIconView(iconType: metadata.iconType, size: 14)
                }

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

// MARK: - Agent Picker Popover

struct AgentPickerPopover: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AgentRegistry.shared.getEnabledAgents(), id: \.id) { agent in
                Button {
                    onSelect(agent.id)
                } label: {
                    HStack(spacing: 8) {
                        AgentIconView(iconType: agent.iconType, size: 16)

                        Text(agent.name)
                            .font(.system(size: 12))

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.001))
                .cornerRadius(4)
            }
        }
        .padding(8)
        .frame(width: 160)
    }
}
