//
//  GitLogView.swift
//  agentmonitor
//
//  Git commit history view
//

import SwiftUI

// MARK: - Author Avatar View

struct AuthorAvatarView: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.6, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(avatarColor)
            )
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]
        let index = abs(initial.hashValue) % colors.count
        return colors[index]
    }
}
