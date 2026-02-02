//
//  AuthorAvatarView.swift
//  oshin
//
//  Author avatar view with Gravatar support
//

import CryptoKit
import SwiftUI

// MARK: - Author Avatar View

struct AuthorAvatarView: View {
    let initial: String
    let size: CGFloat
    var email: String?

    var body: some View {
        if let email = email, let url = gravatarURL(for: email) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure:
                    fallbackAvatar
                case .empty:
                    fallbackAvatar
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                        )
                @unknown default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Text(initial)
            .font(.system(size: size * 0.5, weight: .medium))
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

    private func gravatarURL(for email: String) -> URL? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, let data = trimmedEmail.data(using: .utf8) else { return nil }

        // Use SHA256 as per Gravatar's updated API
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // d=404 returns 404 if no avatar, triggering AsyncImage failure
        let sizeInt = Int(size * 3)  // 3x for retina
        return URL(string: "https://gravatar.com/avatar/\(hashString)?d=404&size=\(sizeInt)")
    }
}
