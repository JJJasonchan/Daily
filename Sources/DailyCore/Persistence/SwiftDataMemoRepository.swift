import Foundation
import SwiftData

@MainActor
public final class SwiftDataMemoRepository: MemoRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func memos() throws -> [Memo] {
        let descriptor = FetchDescriptor<Memo>(
            sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func memo(id: UUID) throws -> Memo? {
        let descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    public func insert(_ memo: Memo) {
        context.insert(memo)
    }

    public func remove(_ memo: Memo) {
        context.delete(memo)
    }

    public func save() throws {
        try context.save()
    }
}
