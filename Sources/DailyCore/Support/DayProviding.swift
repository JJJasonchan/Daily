import Foundation

public protocol DayProviding: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
}
