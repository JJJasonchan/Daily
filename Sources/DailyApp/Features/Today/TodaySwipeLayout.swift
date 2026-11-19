import Foundation

struct TodaySwipeLayout {
    static let gestureThreshold: CGFloat = 10
    static let flickSpeed: CGFloat = 110

    let rowWidth: CGFloat
    var actionWidth: CGFloat { min(80, rowWidth / 2) }
    var drawerWidth: CGFloat { 2 * actionWidth }
    var commitPoint: CGFloat { max(rowWidth * 0.6, drawerWidth + actionWidth / 2) }
    var canCommit: Bool { rowWidth > 0 && commitPoint <= rowWidth }

    func exposure(for raw: CGFloat) -> CGFloat {
        if raw <= drawerWidth { return max(0, raw) }
        let resistance: CGFloat = 0.55
        if !canCommit {
            return drawerWidth + rubberBand(raw - drawerWidth, resistance: resistance)
        }
        let knee = drawerWidth + (commitPoint - drawerWidth) / resistance
        if raw <= knee { return drawerWidth + resistance * (raw - drawerWidth) }
        return min(rowWidth, commitPoint + rubberBand(raw - knee, resistance: resistance))
    }

    func shouldStayOpen(exposure: CGFloat, speed: CGFloat) -> Bool {
        if abs(speed) >= Self.flickSpeed { return speed > 0 }
        return exposure > drawerWidth / 2
    }

    private func rubberBand(_ extra: CGFloat, resistance: CGFloat) -> CGFloat {
        extra * rowWidth * resistance / max(1, rowWidth + resistance * extra)
    }
}
