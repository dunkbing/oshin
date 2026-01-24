//
//  TerminalSessionManager.swift
//  agentmonitor
//
//  Caches terminal instances to prevent recreation on tab switch
//

import AppKit
import Foundation

@MainActor
class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private var terminals: [String: GhosttyTerminalView] = [:]
    private var scrollViews: [String: TerminalScrollView] = [:]

    private init() {}

    // MARK: - Terminal Management

    func getTerminal(for repositoryPath: String) -> GhosttyTerminalView? {
        return terminals[repositoryPath]
    }

    func setTerminal(_ terminal: GhosttyTerminalView, for repositoryPath: String) {
        terminals[repositoryPath] = terminal
    }

    func removeTerminal(for repositoryPath: String) {
        if let terminal = terminals.removeValue(forKey: repositoryPath) {
            terminal.onProcessExit = nil
            terminal.onTitleChange = nil
        }
        scrollViews.removeValue(forKey: repositoryPath)
    }

    // MARK: - Scroll View Management

    func getScrollView(for repositoryPath: String) -> TerminalScrollView? {
        return scrollViews[repositoryPath]
    }

    func setScrollView(_ scrollView: TerminalScrollView, for repositoryPath: String) {
        scrollViews[repositoryPath] = scrollView
    }

    // MARK: - Cleanup

    func removeAll() {
        for (_, terminal) in terminals {
            terminal.onProcessExit = nil
            terminal.onTitleChange = nil
        }
        terminals.removeAll()
        scrollViews.removeAll()
    }
}
