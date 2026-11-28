import AppKit

/// 悬停识别的排队状态，仅在主线程使用。
/// 同一时刻只保留一个在途查询；查询期间到达的鼠标位置只保留最后一个，返回后立即补查。
/// 失效之后返回的旧结果直接丢弃，避免旧鼠标位置的结果覆盖新状态。
@MainActor
final class SnapHoverTracker<Target: Equatable> {
    typealias Query = (
        _ point: NSPoint,
        _ completion: @escaping @MainActor (Target?) -> Void
    ) -> Void
    typealias Handler = @MainActor (_ target: Target?) -> Void

    private(set) var target: Target?
    private var generation: UInt = 0
    private var isQueryInFlight = false
    private var pendingPoint: NSPoint?
    private var query: Query?
    private var handler: Handler?

    /// 识别 `point` 下的目标。已有查询在途时只记下最新的点，不丢弃这次移动。
    func track(_ point: NSPoint, query: @escaping Query, handler: @escaping Handler) {
        self.query = query
        self.handler = handler
        guard !isQueryInFlight else {
            pendingPoint = point
            return
        }
        isQueryInFlight = true
        let generation = self.generation
        query(point) { [weak self] target in
            self?.finishQuery(with: target, generation: generation)
        }
    }

    /// 清空目标并丢弃在途查询与待补查的鼠标位置；返回目标是否发生了变化。
    @discardableResult
    func invalidate() -> Bool {
        generation &+= 1
        isQueryInFlight = false
        pendingPoint = nil
        query = nil
        handler = nil
        guard target != nil else { return false }
        target = nil
        return true
    }

    private func finishQuery(with result: Target?, generation: UInt) {
        guard generation == self.generation, let query, let handler else { return }
        isQueryInFlight = false
        if result != target {
            target = result
            handler(result)
        }
        if let pendingPoint {
            self.pendingPoint = nil
            track(pendingPoint, query: query, handler: handler)
        }
    }
}

typealias WindowSnapHoverTracker = SnapHoverTracker<WindowSnapDetector.Target>
