import Foundation
import AppKit

/// 绘制节流器，用于防止过于频繁的重绘操作
class DisplayThrottler {
    private var lastDisplayTime: CFAbsoluteTime = 0
    private let minimumInterval: TimeInterval
    private var pendingUpdate = false

    init(fps: Double = 60) {
        // 根据目标FPS计算最小间隔
        self.minimumInterval = 1.0 / fps
    }

    /// 请求显示更新，如果距离上次更新的时间太短则忽略
    /// - Returns: 是否应该执行显示更新
    func requestDisplay() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastDisplayTime

        if elapsed >= minimumInterval {
            lastDisplayTime = now
            pendingUpdate = false
            return true
        } else {
            // 标记有待处理的更新
            pendingUpdate = true
            return false
        }
    }

    /// 强制执行显示更新，忽略节流限制
    func forceDisplay() {
        lastDisplayTime = CFAbsoluteTimeGetCurrent()
        pendingUpdate = false
    }

    /// 检查是否有待处理的更新
    var hasPendingUpdate: Bool {
        return pendingUpdate
    }

    /// 重置节流器
    func reset() {
        lastDisplayTime = 0
        pendingUpdate = false
    }
}

/// 带延迟的显示更新管理器
class DelayedDisplayUpdater {
    private var updateTimer: Timer?
    private let delay: TimeInterval
    private let updateHandler: () -> Void

    init(delay: TimeInterval = 0.016, updateHandler: @escaping () -> Void) {
        self.delay = delay
        self.updateHandler = updateHandler
    }

    /// 请求延迟更新
    func requestUpdate() {
        // 取消之前的定时器
        updateTimer?.invalidate()

        // 创建新的延迟更新
        updateTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.updateHandler()
            self?.updateTimer = nil
        }
    }

    /// 立即执行更新并取消延迟
    func executeImmediately() {
        updateTimer?.invalidate()
        updateTimer = nil
        updateHandler()
    }

    /// 取消待处理的更新
    func cancel() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    deinit {
        updateTimer?.invalidate()
    }
}
