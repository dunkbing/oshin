//
//  DiffView.swift
//  agentmonitor
//
//  SwiftUI-based diff viewer
//

import SwiftUI

struct DiffView: View {
    let diffOutput: String
    let fileName: String
    let fontSize: Double

    @State private var lines: [DiffLine] = []

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
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                DiffLineView(line: line, fontSize: fontSize)
                            }
                        }
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
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
