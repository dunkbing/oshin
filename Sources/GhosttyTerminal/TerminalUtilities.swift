//
//  TerminalUtilities.swift
//  oshin
//
//  Utility types for terminal operations
//

import AppKit
import GhosttyKit

// MARK: - Terminal Copy Settings

struct TerminalCopySettings {
    var trimTrailingWhitespace: Bool
    var collapseBlankLines: Bool
    var stripShellPrompts: Bool
    var flattenCommands: Bool
    var removeBoxDrawing: Bool
    var stripAnsiCodes: Bool
}

// MARK: - Terminal Text Cleaner

enum TerminalTextCleaner {
    static func cleanText(_ text: String, settings: TerminalCopySettings) -> String {
        var result = text

        if settings.stripAnsiCodes {
            // Remove ANSI escape codes
            result = result.replacingOccurrences(
                of: "\\x1B\\[[0-9;]*[a-zA-Z]",
                with: "",
                options: .regularExpression
            )
        }

        if settings.trimTrailingWhitespace {
            result = result.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        }

        if settings.collapseBlankLines {
            result = result.replacingOccurrences(
                of: "\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
        }

        return result
    }
}

// MARK: - Clipboard

enum Clipboard {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    static func getString() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    static func readString() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
}
