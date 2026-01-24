import Foundation
import SwiftData

@Model
final class Repository {
    var id: UUID
    var name: String
    var path: String
    var status: String
    var lastUpdated: Date?

    var workspace: Workspace?

    init(name: String, path: String, status: String = "active") {
        self.id = UUID()
        self.name = name
        self.path = path
        self.status = status
        self.lastUpdated = Date()
    }
}
