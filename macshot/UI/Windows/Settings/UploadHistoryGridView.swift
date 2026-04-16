import SwiftUI

/// Upload history grid view with filtering and virtualization
struct UploadHistoryGridView: View {
    @State private var selectedFilter: UploadFilter = .all
    @State private var history: [UploadHistoryItem] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    // 自适应网格：每个 item 最小 100px，最大 120px
    let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：筛选器 + 清空按钮
            HStack {
                Picker("", selection: $selectedFilter) {
                    ForEach(UploadFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .onChange(of: selectedFilter) { _ in
                    loadHistory()
                }

                Spacer()

                Button(role: .destructive) {
                    clearAllHistory()
                } label: {
                    Label("清空记录", systemImage: "trash")
                }
                .disabled(history.isEmpty)
            }
            .padding()

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
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(history) { item in
                            UploadHistoryCell(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            loadHistory()
        }
    }

    private func loadHistory() {
        isLoading = true

        Task {
            // 从 UserDefaults 加载上传历史
            let uploads = UploadHistoryStore.load()

            // 根据筛选条件过滤
            let filtered: [[String: String]]
            switch selectedFilter {
            case .all:
                filtered = uploads
            case .gdrive:
                filtered = uploads.filter { $0["provider"] == "gdrive" }
            case .imgbb:
                filtered = uploads.filter { $0["provider"] == "imgbb" }
            case .s3:
                filtered = uploads.filter { $0["provider"] == "s3" }
            }

            // 转换为 UploadHistoryItem
            let items = filtered.map { dict -> UploadHistoryItem in
                UploadHistoryItem(
                    id: UUID().uuidString,
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

/// Upload filter options
enum UploadFilter: String, CaseIterable {
    case all = "全部"
    case gdrive = "Google Drive"
    case imgbb = "ImgBB"
    case s3 = "S3"
}
