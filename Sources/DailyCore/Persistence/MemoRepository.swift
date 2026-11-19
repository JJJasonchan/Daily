import Foundation

@MainActor
public protocol MemoRepository: AnyObject {
    func memos() throws -> [Memo]
    func memo(id: UUID) throws -> Memo?
    func insert(_ memo: Memo)
    func remove(_ memo: Memo)
    func save() throws
}
