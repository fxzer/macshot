import Foundation

/// 弱引用控制器集合，用于避免循环引用和内存泄漏
class WeakControllerSet<T: AnyObject> {
    private var storage = NSHashTable<AnyObject>.weakObjects()

    /// 添加控制器
    func add(_ controller: T) {
        storage.add(controller)
    }

    /// 移除指定控制器
    func remove(_ controller: T) {
        storage.remove(controller)
    }

    /// 移除满足条件的控制器
    func removeAll(where predicate: (T) -> Bool) {
        for controller in allObjects where predicate(controller) {
            storage.remove(controller)
        }
    }

    /// 清空所有控制器
    func removeAll() {
        storage.removeAllObjects()
    }

    /// 获取所有存活的控制器
    var allObjects: [T] {
        storage.allObjects.compactMap { $0 as? T }
    }

    /// 检查是否为空
    var isEmpty: Bool {
        allObjects.isEmpty
    }

    /// 控制器数量
    var count: Int {
        allObjects.count
    }

    /// 执行清理操作，移除已释放的控制器
    func cleanup() {
        // NSHashTable会自动清理，这里只是确保同步
        _ = allObjects
    }
}
