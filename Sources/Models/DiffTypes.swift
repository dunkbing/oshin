//
//  DiffTypes.swift
//  agentmonitor
//
//  Shared diff line types and models
//

import AppKit
import SwiftUI

// MARK: - Diff Line Type

enum DiffLineType: String, Hashable, Codable, Sendable {
    case added
    case deleted
    case context
    case header

    var marker: String {
        switch self {
        case .added: return "+"
        case .deleted: return "-"
        case .context: return " "
        case .header: return ""
        }
    }

    var markerColor: Color {
        switch self {
        case .added: return .green
        case .deleted: return .red
        case .context: return .clear
        case .header: return .secondary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added: return Color.green.opacity(0.2)
        case .deleted: return Color.red.opacity(0.2)
        case .context: return .clear
        case .header: return Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }

    var nsMarkerColor: NSColor {
        switch self {
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .context: return .tertiaryLabelColor
        case .header: return .systemBlue
        }
    }

    var nsBackgroundColor: NSColor {
        switch self {
        case .added: return NSColor.systemGreen.withAlphaComponent(0.15)
        case .deleted: return NSColor.systemRed.withAlphaComponent(0.15)
        case .context: return .clear
        case .header: return NSColor.systemBlue.withAlphaComponent(0.1)
        }
    }
}

// MARK: - Diff Line

struct DiffLine: Identifiable, Hashable, Sendable {
    let lineNumber: Int
    let oldLineNumber: String?
    let newLineNumber: String?
    let content: String
    let type: DiffLineType

    var id: Int { lineNumber }

    func hash(into hasher: inout Hasher) {
        hasher.combine(lineNumber)
        hasher.combine(content)
        hasher.combine(type)
    }

    static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
        lhs.lineNumber == rhs.lineNumber && lhs.content == rhs.content && lhs.type == rhs.type
    }
}

// MARK: - Diff Line Parser

struct DiffLineParser {
    private let rawLines: [String]

    init(rawLines: [String]) {
        self.rawLines = rawLines
    }

    init(diffOutput: String) {
        self.rawLines = diffOutput.components(separatedBy: .newlines)
    }

    func parseAll() -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldNum = 0
        var newNum = 0

        for (index, line) in rawLines.enumerated() {
            if line.hasPrefix("@@") {
                // Parse hunk header
                if let (parsedOld, parsedNew) = parseHunkHeader(line) {
                    oldNum = parsedOld - 1
                    newNum = parsedNew - 1
                }
                lines.append(
                    DiffLine(
                        lineNumber: index,
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        content: line,
                        type: .header
                    ))
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                newNum += 1
                lines.append(
                    DiffLine(
                        lineNumber: index,
                        oldLineNumber: nil,
                        newLineNumber: String(newNum),
                        content: String(line.dropFirst()),
                        type: .added
                    ))
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                oldNum += 1
                lines.append(
                    DiffLine(
                        lineNumber: index,
                        oldLineNumber: String(oldNum),
                        newLineNumber: nil,
                        content: String(line.dropFirst()),
                        type: .deleted
                    ))
            } else if line.hasPrefix(" ") {
                oldNum += 1
                newNum += 1
                lines.append(
                    DiffLine(
                        lineNumber: index,
                        oldLineNumber: String(oldNum),
                        newLineNumber: String(newNum),
                        content: String(line.dropFirst()),
                        type: .context
                    ))
            } else if line.hasPrefix("diff --git") || line.hasPrefix("index ") || line.hasPrefix("---")
                || line.hasPrefix("+++")
            {
                // Skip diff headers
                continue
            }
        }

        return lines
    }

    private func parseHunkHeader(_ line: String) -> (old: Int, new: Int)? {
        var oldNum = 0
        var newNum = 0

        if let minusRange = line.range(of: "-") {
            let afterMinus = line[minusRange.upperBound...]
            if let end = afterMinus.firstIndex(where: { $0 == "," || $0 == " " }),
                let num = Int(afterMinus[..<end])
            {
                oldNum = num
            }
        }

        if let plusRange = line.range(of: " +") {
            let afterPlus = line[plusRange.upperBound...]
            if let end = afterPlus.firstIndex(where: { $0 == "," || $0 == " " }),
                let num = Int(afterPlus[..<end])
            {
                newNum = num
            }
        }

        return (oldNum, newNum)
    }
}
