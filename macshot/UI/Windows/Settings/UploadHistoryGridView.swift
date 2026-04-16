import SwiftUI

/// Upload history grid view with filtering and virtualization
struct UploadHistoryGridView: View {
    let selectedProvider: String
    @State private var history: [UploadHistoryItem] = []
    @State private var isLoading = false

    // 固定 5 列网格，图片尺寸 80px
    let columns = [GridItem(.flexible(), spacing: 4),
                   GridItem(.flexible(), spacing: 4),
                   GridItem(.flexible(), spacing: 4),
                   GridItem(.flexible(), spacing: 4),
                   GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：标题 + 清空按钮
            HStack(alignment: .center) {
                Text("上传历史")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(role: .destructive) {
                    clearAllHistory()
                } label: {
                    Text("清空记录")
                }
                .disabled(history.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // 虚拟化自适应网格
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无上传记录")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(history) { item in
                        UploadHistoryCell(item: item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            loadHistory()
        }
        .onChange(of: selectedProvider) { _ in
            loadHistory()
        }
    }

    private func loadHistory() {
        isLoading = true

        Task {
            // 从 UserDefaults 加载上传历史
            let uploads = UploadHistoryStore.load()

            // 根据 selectedProvider 过滤
            let filtered = uploads.filter { $0["provider"] == selectedProvider }

            // 转换为 UploadHistoryItem
            let items = filtered.map { dict -> UploadHistoryItem in
                // 使用存储的 ID，如果没有则生成新 ID（兼容旧数据）
                let id = dict["id"] ?? UUID().uuidString
                return UploadHistoryItem(
                    id: id,
                    provider: dict["provider"] ?? "unknown",
                    link: dict["link"] ?? "",
                    deleteURL: dict["deleteURL"] ?? "",
                    timestamp: Date()
                )
            }

            await MainActor.run {
                self.history = items
                self.isLoading = false
            }
        }
    }

    // 物理清空历史记录（删除整个文件夹）
    private func clearAllHistory() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let historyDir = appSupportURL.appendingPathComponent("com.fxzer.macshot/history")

        Task.detached(priority: .background) {
            do {
                if fileManager.fileExists(atPath: historyDir.path) {
                    try fileManager.removeItem(at: historyDir)
                }
                try fileManager.createDirectory(at: historyDir, withIntermediateDirectories: true)

                let emptyIndexURL = historyDir.appendingPathComponent("index.json")
                try "[]".write(to: emptyIndexURL, atomically: true, encoding: .utf8)

                await MainActor.run {
                    withAnimation {
                        self.history.removeAll()
                    }
                }
            } catch {
                print("清理历史缓存失败: \(error.localizedDescription)")
            }
        }
    }
}

