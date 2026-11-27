import Cocoa

@main
struct CaptureLatencyTests {
    @MainActor
    static func checkWatchdog() {
        let watchdog = CaptureRequestWatchdog()
        var timeouts = 0
        watchdog.start(timeout: 0.01) { timeouts += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(timeouts == 1, "未释放超时请求")
        watchdog.start(timeout: 0.01) { timeouts += 1 }
        watchdog.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(timeouts == 1, "取消后的超时回调仍在执行")
        watchdog.start(timeout: 0.01) { timeouts += 10 }
        watchdog.start(timeout: 0.01) { timeouts += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(timeouts == 2, "旧请求的超时回调影响了新请求")
        print("PASS: 超时释放、取消、替换请求")
    }

    @MainActor
    static func main() async {
        checkWatchdog()
        var heartbeatDelivered = false
        let capture = Task { @MainActor in
            let image = await WindowListDisplaySnapshot.captureDisplayInBackground(
                CGMainDisplayID(), excludingWindowIDs: [1]
            )
            precondition(heartbeatDelivered, "同步屏幕捕获阻塞了主线程")
            return image
        }
        Task { @MainActor in heartbeatDelivered = true }
        let image = await capture.value
        precondition(image != nil && image!.width > 0, "后台捕获未返回有效截图")
        print("PASS: 后台捕获有效截图，等待期间主线程继续处理任务")
    }
}
