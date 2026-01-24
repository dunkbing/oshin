//
//  GitStatusView.swift
//  agentmonitor
//
//  Displays git status (additions/deletions/untracked)
//

import SwiftUI

struct GitStatusView: View {
    let additions: Int
    let deletions: Int
    let untrackedFiles: Int

    var body: some View {
        HStack(spacing: 8) {
            if additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            if deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            if untrackedFiles > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(untrackedFiles)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: additions)
        .animation(.easeInOut(duration: 0.2), value: deletions)
        .animation(.easeInOut(duration: 0.2), value: untrackedFiles)
    }
}
