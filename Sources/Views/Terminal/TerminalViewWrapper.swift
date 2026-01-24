//
//  TerminalViewWrapper.swift
//  agentmonitor
//
//  SwiftUI wrapper for GhosttyTerminalView
//

import AppKit
import GhosttyKit
import SwiftUI

// MARK: - Terminal View Coordinator

class TerminalViewCoordinator {
    let repositoryPath: String
    let onProcessExit: () -> Void
    private var exitCheckTimer: Timer?

    init(repositoryPath: String, onProcessExit: @escaping () -> Void) {
        self.repositoryPath = repositoryPath
        self.onProcessExit = onProcessExit
    }

    func startMonitoring(terminal: GhosttyTerminalView) {
        stopMonitoring()
        // Poll for process exit every 500ms
        exitCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self, weak terminal] _ in
            Task { @MainActor [weak self, weak terminal] in
                guard let self = self, let terminal = terminal else { return }

                if terminal.processExited {
                    self.exitCheckTimer?.invalidate()
                    self.exitCheckTimer = nil
                    self.onProcessExit()
                }
            }
        }
        exitCheckTimer?.tolerance = 0.1
    }

    func stopMonitoring() {
        exitCheckTimer?.invalidate()
        exitCheckTimer = nil
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Terminal View Wrapper

struct TerminalViewWrapper: NSViewRepresentable {
    let workingDirectory: String
    @ObservedObject var ghosttyApp: Ghostty.App
    let sessionManager: TerminalSessionManager
    let onProcessExit: () -> Void
    let onTitleChange: (String) -> Void
    let shouldFocus: Bool
    let isFocused: Bool
    let focusVersion: Int
    let size: CGSize

    func makeCoordinator() -> TerminalViewCoordinator {
        TerminalViewCoordinator(repositoryPath: workingDirectory, onProcessExit: onProcessExit)
    }

    func makeNSView(context: Context) -> NSView {
        // Check if terminal already exists
        if let existingTerminal = sessionManager.getTerminal(for: workingDirectory) {
            context.coordinator.startMonitoring(terminal: existingTerminal)

            DispatchQueue.main.async {
                existingTerminal.onProcessExit = onProcessExit
                existingTerminal.onTitleChange = onTitleChange
                existingTerminal.needsLayout = true
                existingTerminal.layoutSubtreeIfNeeded()
            }

            // Get or create scroll view wrapper
            if let scrollView = sessionManager.getScrollView(for: workingDirectory) {
                return scrollView
            }

            // Create scroll view wrapper for existing terminal
            let scrollView = TerminalScrollView(contentSize: size, surfaceView: existingTerminal)
            sessionManager.setScrollView(scrollView, for: workingDirectory)
            return scrollView
        }

        // Ensure Ghostty app is ready
        guard let app = ghosttyApp.app else {
            let placeholder = NSView()
            placeholder.wantsLayer = true
            placeholder.layer?.backgroundColor = NSColor.black.cgColor
            return placeholder
        }

        // Create new Ghostty terminal
        let terminalView = GhosttyTerminalView(
            frame: CGRect(origin: .zero, size: size),
            worktreePath: workingDirectory,
            ghosttyApp: app,
            appWrapper: ghosttyApp
        )
        terminalView.onProcessExit = onProcessExit
        terminalView.onTitleChange = onTitleChange

        // Store terminal in manager
        sessionManager.setTerminal(terminalView, for: workingDirectory)

        // Start monitoring for process exit
        context.coordinator.startMonitoring(terminal: terminalView)

        // Wrap in scroll view
        let scrollView = TerminalScrollView(contentSize: size, surfaceView: terminalView)
        sessionManager.setScrollView(scrollView, for: workingDirectory)

        return scrollView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update frame size
        if nsView.frame.size != size || nsView.frame.origin != .zero {
            nsView.frame = CGRect(origin: .zero, size: size)
            nsView.needsLayout = true
            nsView.layoutSubtreeIfNeeded()
        }

        // Get the terminal view
        let terminalView: GhosttyTerminalView?
        if let scrollView = nsView as? TerminalScrollView {
            terminalView = scrollView.surfaceView
        } else {
            terminalView = nsView as? GhosttyTerminalView
        }

        // Handle focus
        if let terminalView = terminalView {
            if shouldFocus {
                guard let window = nsView.window else { return }
                window.makeFirstResponder(terminalView)
            } else if !isFocused && nsView.window?.firstResponder == terminalView {
                nsView.window?.makeFirstResponder(nil)
            }

            // Keep callbacks up to date
            terminalView.onProcessExit = onProcessExit
            terminalView.onTitleChange = onTitleChange
        }
    }
}
