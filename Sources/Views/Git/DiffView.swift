//
//  DiffView.swift
//  oshin
//
//  SwiftUI-based diff viewer
//

import SwiftUI

// MARK: - Diff View Mode

enum DiffViewMode: String, CaseIterable {
    case unified = "unified"
    case split = "split"

    var icon: String {
        switch self {
        case .unified: return "text.alignleft"
        case .split: return "rectangle.split.2x1"
        }
    }

    var label: String {
        switch self {
        case .unified: return "Unified"
        case .split: return "Split"
        }
    }
}

struct DiffView: View {
    let diffOutput: String
    let fileName: String
    let fontSize: Double

    @State private var lines: [DiffLine] = []
    @AppStorage("diffViewMode") private var viewMode: DiffViewMode = .unified

    var body: some View {
        VStack(spacing: 0) {
            // File header
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(fileName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                Spacer()

                // View mode toggle
                if !lines.isEmpty {
                    Picker("", selection: $viewMode) {
                        ForEach(DiffViewMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 70)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Diff content
            if lines.isEmpty && diffOutput.isEmpty {
                ContentUnavailableView(
                    "No Diff",
                    systemImage: "doc.text",
                    description: Text("Select a file to view changes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        switch viewMode {
                        case .unified:
                            UnifiedDiffView(lines: lines, fontSize: fontSize)
                                .frame(
                                    minWidth: geometry.size.width, minHeight: geometry.size.height,
                                    alignment: .topLeading)
                        case .split:
                            SplitDiffView(lines: lines, fontSize: fontSize, containerWidth: geometry.size.width)
                                .frame(
                                    minWidth: geometry.size.width, minHeight: geometry.size.height,
                                    alignment: .topLeading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            parseLines()
        }
        .onChange(of: diffOutput) { _, _ in
            parseLines()
        }
    }

    private func parseLines() {
        guard !diffOutput.isEmpty else {
            lines = []
            return
        }

        let parser = DiffLineParser(diffOutput: diffOutput)
        lines = parser.parseAll()
    }
}

// MARK: - Unified Diff View

struct UnifiedDiffView: View {
    let lines: [DiffLine]
    let fontSize: Double

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                DiffLineView(line: line, fontSize: fontSize)
            }
        }
    }
}

// MARK: - Split Diff View

struct SplitDiffView: View {
    let lines: [DiffLine]
    let fontSize: Double
    var containerWidth: CGFloat? = nil

    var body: some View {
        let sidePairs = buildSideBySidePairs()

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sidePairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 0) {
                    SplitDiffLineView(
                        line: pair.left,
                        fontSize: fontSize,
                        showOldLineNumber: true
                    )
                    .frame(width: containerWidth.map { $0 / 2 }, alignment: .leading)
                    .frame(maxWidth: containerWidth == nil ? .infinity : nil, alignment: .leading)

                    Divider()

                    SplitDiffLineView(
                        line: pair.right,
                        fontSize: fontSize,
                        showOldLineNumber: false
                    )
                    .frame(width: containerWidth.map { $0 / 2 }, alignment: .leading)
                    .frame(maxWidth: containerWidth == nil ? .infinity : nil, alignment: .leading)
                }
            }
        }
    }

    private func buildSideBySidePairs() -> [(left: DiffLine?, right: DiffLine?)] {
        var pairs: [(left: DiffLine?, right: DiffLine?)] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            switch line.type {
            case .header:
                // Headers span both sides
                pairs.append((left: line, right: line))
                i += 1

            case .context:
                // Context lines appear on both sides
                pairs.append((left: line, right: line))
                i += 1

            case .deleted:
                // Collect consecutive deletions and additions
                var deletions: [DiffLine] = []
                var additions: [DiffLine] = []

                while i < lines.count && lines[i].type == .deleted {
                    deletions.append(lines[i])
                    i += 1
                }

                while i < lines.count && lines[i].type == .added {
                    additions.append(lines[i])
                    i += 1
                }

                // Pair them up
                let maxCount = max(deletions.count, additions.count)
                for j in 0..<maxCount {
                    let left = j < deletions.count ? deletions[j] : nil
                    let right = j < additions.count ? additions[j] : nil
                    pairs.append((left: left, right: right))
                }

            case .added:
                // Standalone addition (no preceding deletion)
                pairs.append((left: nil, right: line))
                i += 1
            }
        }

        return pairs
    }
}

struct SplitDiffLineView: View {
    let line: DiffLine?
    let fontSize: Double
    let showOldLineNumber: Bool

    var body: some View {
        if let line = line {
            HStack(spacing: 0) {
                // Line number
                Text(showOldLineNumber ? (line.oldLineNumber ?? "") : (line.newLineNumber ?? ""))
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)

                // Marker
                if line.type != .header && line.type != .context {
                    Text(line.type.marker)
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(line.type.markerColor)
                        .frame(width: 16)
                } else {
                    Text(" ")
                        .font(.system(size: fontSize, design: .monospaced))
                        .frame(width: 16)
                }

                // Content
                Text(line.content)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 8)
            .background(backgroundColor(for: line))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Empty line placeholder
            HStack(spacing: 0) {
                Text("")
                    .font(.system(size: fontSize, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)

                Text(" ")
                    .font(.system(size: fontSize, design: .monospaced))
                    .frame(width: 16)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func backgroundColor(for line: DiffLine) -> Color {
        switch line.type {
        case .added: return Color.green.opacity(0.2)
        case .deleted: return Color.red.opacity(0.2)
        case .context: return .clear
        case .header: return Color(nsColor: .controlBackgroundColor).opacity(0.3)
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine
    let fontSize: Double

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber ?? "")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 4)

            // New line number
            Text(line.newLineNumber ?? "")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // Marker
            Text(line.type.marker)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(line.type.markerColor)
                .frame(width: 16)

            // Content
            Text(line.content)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
        .background(line.type.backgroundColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty State

struct DiffEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Select a file to view diff")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image Diff View

struct ImageDiffView: View {
    let oldImageData: Data?
    let newImageData: Data?
    let changeType: CommitFileChange.FileChangeType
    let viewMode: DiffViewMode

    var body: some View {
        Group {
            switch viewMode {
            case .split:
                // Side by side
                HStack(spacing: 16) {
                    // Old image
                    if changeType != .added {
                        ImagePanel(
                            label: "Before",
                            imageData: oldImageData,
                            borderColor: .red
                        )
                    }

                    // New image
                    if changeType != .deleted {
                        ImagePanel(
                            label: "After",
                            imageData: newImageData,
                            borderColor: .green
                        )
                    }
                }
            case .unified:
                // Top / bottom
                VStack(spacing: 16) {
                    // Old image
                    if changeType != .added {
                        ImagePanel(
                            label: "Before",
                            imageData: oldImageData,
                            borderColor: .red
                        )
                    }

                    // New image
                    if changeType != .deleted {
                        ImagePanel(
                            label: "After",
                            imageData: newImageData,
                            borderColor: .green
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Image Panel

struct ImagePanel: View {
    let label: String
    let imageData: Data?
    let borderColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let data = imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor.opacity(0.5), lineWidth: 2)
                    )
            } else {
                ImagePlaceholder(message: "Image not available")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Image Placeholder

struct ImagePlaceholder: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 200, height: 150)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Binary File Placeholder

struct BinaryFilePlaceholder: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Binary file")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            Spacer()
        }
        .background(Color.primary.opacity(0.02))
    }
}
