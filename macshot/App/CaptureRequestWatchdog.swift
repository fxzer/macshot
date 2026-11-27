import Foundation

/// 防止系统捕获迟迟不返回时，截图会话一直占用入口。
@MainActor
final class CaptureRequestWatchdog {
    private var timer: Timer?

    func start(timeout: TimeInterval = 3, onTimeout: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                onTimeout()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
