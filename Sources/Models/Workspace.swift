import Foundation
import SwiftData

@Model
final class Workspace {
    var id: UUID
    var name: String
    var colorHex: String
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \Repository.workspace)
    var repositories: [Repository]

    init(name: String, colorHex: String = "#007AFF", order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.repositories = []
    }
}
