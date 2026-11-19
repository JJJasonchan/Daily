import Foundation

public enum MemoServiceError: Error, Equatable {
    case emptyBody
    case memoNotFound
}

@MainActor
public final class MemoService {
    private let repository: any MemoRepository

    public init(repository: any MemoRepository) {
        self.repository = repository
    }

    public func memos() throws -> [Memo] {
        try repository.memos()
    }

    public func memo(id: UUID) throws -> Memo? {
        try repository.memo(id: id)
    }

    public func create(_ body: String, now: Date = .now) throws -> Memo {
        let trimmed = try validatedBody(body)
        let memo = Memo(body: trimmed, createdAt: now, updatedAt: now)
        repository.insert(memo)
        try repository.save()
        return memo
    }

    public func update(id: UUID, body: String, now: Date = .now) throws {
        let trimmed = try validatedBody(body)
        guard let memo = try repository.memo(id: id) else {
            throw MemoServiceError.memoNotFound
        }
        memo.body = trimmed
        memo.updatedAt = now
        try repository.save()
    }

    public func delete(id: UUID) throws {
        guard let memo = try repository.memo(id: id) else {
            throw MemoServiceError.memoNotFound
        }
        repository.remove(memo)
        try repository.save()
    }

    private func validatedBody(_ body: String) throws -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MemoServiceError.emptyBody
        }
        return trimmed
    }
}
