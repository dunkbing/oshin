//
//  ChatUtilities.swift
//  oshin
//
//  Utility helpers for chat views
//

import Foundation

// MARK: - Date Formatters

@MainActor
enum DateFormatters {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Convenience wrapper that returns a formatted relative date string
    static let relative: RelativeDateFormatter = RelativeDateFormatter()
}

/// Wrapper for RelativeDateTimeFormatter with a simpler string(from:) interface
@MainActor
struct RelativeDateFormatter {
    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Duration Formatter

enum DurationFormatter {
    static func short(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Code Block Parser

struct CodeBlock: Identifiable {
    let id = UUID()
    let language: String?
    let code: String
    let range: Range<String.Index>
}

enum CodeBlockParser {
    private static let codeBlockPattern = #"```(\w*)\n([\s\S]*?)```"#

    static func parse(_ content: String) -> [CodeBlock] {
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else {
            return []
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        return matches.compactMap { match -> CodeBlock? in
            guard let fullRange = Range(match.range, in: content),
                let langRange = Range(match.range(at: 1), in: content),
                let codeRange = Range(match.range(at: 2), in: content)
            else {
                return nil
            }

            let language = String(content[langRange])
            let code = String(content[codeRange])

            return CodeBlock(
                language: language.isEmpty ? nil : language,
                code: code.trimmingCharacters(in: .newlines),
                range: fullRange
            )
        }
    }

    /// Splits content into text and code block segments
    static func segments(_ content: String) -> [ContentSegment] {
        let codeBlocks = parse(content)
        guard !codeBlocks.isEmpty else {
            return [.text(content)]
        }

        var segments: [ContentSegment] = []
        var currentIndex = content.startIndex

        for block in codeBlocks {
            // Add text before code block
            if currentIndex < block.range.lowerBound {
                let textPart = String(content[currentIndex..<block.range.lowerBound])
                let trimmed = textPart.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(.text(textPart))
                }
            }

            // Add code block
            segments.append(.code(block))
            currentIndex = block.range.upperBound
        }

        // Add remaining text
        if currentIndex < content.endIndex {
            let textPart = String(content[currentIndex...])
            let trimmed = textPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(.text(textPart))
            }
        }

        return segments
    }
}

enum ContentSegment: Identifiable {
    case text(String)
    case code(CodeBlock)

    var id: String {
        switch self {
        case .text(let str):
            return "text-\(str.hashValue)"
        case .code(let block):
            return block.id.uuidString
        }
    }
}
