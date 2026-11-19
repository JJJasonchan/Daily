import Foundation
import SwiftData

@Model
public final class Memo {
    @Attribute(.unique) public var id: UUID
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
