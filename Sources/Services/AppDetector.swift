//
//  AppDetector.swift
//  oshin
//
//  Detects installed terminals and editors
//

import AppKit
import Foundation

struct DetectedApp: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let path: URL
    let icon: NSImage?
    let category: AppCategory

    static func == (lhs: DetectedApp, rhs: DetectedApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

enum AppCategory: String {
    case terminal = "Terminal"
    case editor = "Editor"
    case finder = "System"
}

@MainActor
class AppDetector: ObservableObject {
    static let shared = AppDetector()

    @Published private(set) var detectedApps: [DetectedApp] = []

    private let knownApps: [(name: String, bundleId: String, category: AppCategory)] = [
        // System
        ("Finder", "com.apple.finder", .finder),

        // Terminals
        ("Terminal", "com.apple.Terminal", .terminal),
        ("iTerm", "com.googlecode.iterm2", .terminal),
        ("Warp", "dev.warp.Warp-Stable", .terminal),
        ("Alacritty", "org.alacritty", .terminal),
        ("Kitty", "net.kovidgoyal.kitty", .terminal),
        ("Hyper", "co.zeit.hyper", .terminal),
        ("Ghostty", "com.mitchellh.ghostty", .terminal),
        ("Rio", "com.raphamorim.rio", .terminal),

        // Editors - Primary
        ("Xcode", "com.apple.dt.Xcode", .editor),
        ("Visual Studio Code", "com.microsoft.VSCode", .editor),
        ("VSCodium", "com.vscodium", .editor),
        ("Cursor", "com.todesktop.230313mzl4w4u92", .editor),
        ("Windsurf", "com.codeium.windsurf", .editor),

        // Editors - Text
        ("Sublime Text", "com.sublimetext.4", .editor),
        ("Nova", "com.panic.Nova", .editor),
        ("TextMate", "com.macromates.TextMate", .editor),
        ("Zed", "dev.zed.Zed", .editor),
        ("BBEdit", "com.barebones.bbedit", .editor),
        ("CotEditor", "com.coteditor.CotEditor", .editor),
        ("MacVim", "org.vim.MacVim", .editor),
        ("TextEdit", "com.apple.TextEdit", .editor),

        // JetBrains IDEs
        ("Android Studio", "com.google.android.studio", .editor),
        ("IntelliJ IDEA", "com.jetbrains.intellij", .editor),
        ("IntelliJ IDEA CE", "com.jetbrains.intellij.ce", .editor),
        ("WebStorm", "com.jetbrains.WebStorm", .editor),
        ("PyCharm", "com.jetbrains.pycharm", .editor),
        ("PyCharm CE", "com.jetbrains.pycharm.ce", .editor),
        ("CLion", "com.jetbrains.CLion", .editor),
        ("GoLand", "com.jetbrains.goland", .editor),
        ("PhpStorm", "com.jetbrains.PhpStorm", .editor),
        ("Rider", "com.jetbrains.rider", .editor),
        ("RustRover", "com.jetbrains.rustrover", .editor),
        ("Fleet", "fleet.Foundation", .editor),
    ]

    private init() {
        detectApps()
    }

    func detectApps() {
        var apps: [DetectedApp] = []

        for (name, bundleId, category) in knownApps {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                let app = DetectedApp(
                    name: name,
                    bundleIdentifier: bundleId,
                    path: appURL,
                    icon: icon,
                    category: category
                )
                apps.append(app)
            }
        }

        detectedApps = apps
    }

    func getApps(for category: AppCategory) -> [DetectedApp] {
        detectedApps.filter { $0.category == category }
    }

    func getTerminals() -> [DetectedApp] {
        getApps(for: .terminal)
    }

    func getEditors() -> [DetectedApp] {
        getApps(for: .editor)
    }

    func getFinder() -> DetectedApp? {
        getApps(for: .finder).first
    }

    func openPath(_ path: String, with app: DetectedApp) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: app.path,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
