import SwiftUI

struct UploadsSettingsView: View {
    // Provider
    @AppStorage("uploadProvider") private var uploadProvider = "imgbb"
    @AppStorage("uploadConfirmEnabled") private var uploadConfirmEnabled = true

    // imgbb
    @State private var imgbbAPIKey = ""

    // S3 fields
    @AppStorage("s3Endpoint") private var s3Endpoint = ""
    @AppStorage("s3Region") private var s3Region = "auto"
    @AppStorage("s3Bucket") private var s3Bucket = ""
    @State private var s3AccessKeyID = ""
    @State private var s3SecretAccessKey = ""
    @AppStorage("s3PublicURLBase") private var s3PublicURLBase = ""
    @AppStorage("s3PathPrefix") private var s3PathPrefix = ""

    // Google Drive state
    @State private var gdriveEmail: String = ""
    @State private var gdriveSignedIn: Bool = false
    @State private var gdriveErrorMessage: String = ""

    // S3 test state
    @State private var s3Testing = false
    @State private var s3StatusMessage = ""
    @State private var s3StatusColor: Color = .secondary

    init() {
        // Load secrets during init to avoid repeated Keychain access
        _imgbbAPIKey = State(initialValue: KeychainStore.string(forKey: "upload.imgbb.apiKey", legacyUserDefaultsKey: "imgbbAPIKey") ?? "")
        _s3AccessKeyID = State(initialValue: KeychainStore.string(forKey: "upload.s3.accessKeyID", legacyUserDefaultsKey: "s3AccessKeyID") ?? "")
        _s3SecretAccessKey = State(initialValue: KeychainStore.string(forKey: "upload.s3.secretAccessKey", legacyUserDefaultsKey: "s3SecretAccessKey") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // MARK: - Upload Service
                Section {
                    Toggle(L("Confirm before uploading"), isOn: $uploadConfirmEnabled)
                    Picker(L("Upload provider"), selection: $uploadProvider) {
                        Text("ImgBB").tag("imgbb")
                        Text("Google Drive").tag("gdrive")
                        Text("S3 兼容存储").tag("s3")
                    }
                    UploadHistoryRow()
                } header: {
                    Text(L("Upload Service"))
                }

                // MARK: - Service Configuration (dynamic)
                if uploadProvider == "imgbb" {
                    Section {
                    SecureField(L("API key"), text: $imgbbAPIKey, prompt: Text(L("Paste your API key")))
                        .font(.system(.body, design: .monospaced))
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("ImgBB Configuration"))
                        HStack(spacing: 4) {
                            Text(L("Accessible in mainland China. Get your free API key at "))
                            Link("imgbb.com", destination: URL(string: "https://api.imgbb.com/")!)
                                .foregroundStyle(Color.settingsSystemAccent)
                            Text(L(". (Images ✓, Videos ✗)"))
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
            }

            if uploadProvider == "gdrive" {
                Section {
                    HStack {
                        Text(L("Account"))
                        Spacer()
                        Text(gdriveSignedIn ? (gdriveEmail.isEmpty ? L("Signed in") : gdriveEmail) : L("Not signed in"))
                            .foregroundColor(gdriveSignedIn ? .primary : .secondary)
                    }
                    Button(gdriveSignedIn ? L("Sign Out") : L("Sign In with Google")) {
                        gdriveSignInAction()
                    }
                    if !gdriveErrorMessage.isEmpty {
                        Text(gdriveErrorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Google Drive Configuration"))
                        Text(L("Files are uploaded to a \"macshot\" folder in your Google Drive. Everything stays private. (Images ✓, Videos ✓)"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if uploadProvider == "s3" {
                Section {
                    TextField(L("Endpoint"), text: $s3Endpoint, prompt: Text("https://abc123.r2.cloudflarestorage.com"))
                        .font(.system(.body, design: .monospaced))
                    TextField(L("Region"), text: $s3Region, prompt: Text("auto"))
                        .font(.system(.body, design: .monospaced))
                    TextField(L("Bucket"), text: $s3Bucket, prompt: Text("my-bucket"))
                        .font(.system(.body, design: .monospaced))
                    TextField(L("Access Key"), text: $s3AccessKeyID, prompt: Text("AKIAIOSFODNN7EXAMPLE"))
                        .font(.system(.body, design: .monospaced))
                    SecureField(L("Secret Key"), text: $s3SecretAccessKey, prompt: Text("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"))
                        .font(.system(.body, design: .monospaced))
                    TextField(L("Public URL"), text: $s3PublicURLBase, prompt: Text("https://cdn.example.com"))
                        .font(.system(.body, design: .monospaced))
                    TextField(L("Path Prefix"), text: $s3PathPrefix, prompt: Text("screenshots/"))
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Text(L("Connection Test"))
                        Spacer()
                        Button(L("Test")) {
                            s3TestConnection()
                        }
                        .disabled(s3Testing)
                        if !s3StatusMessage.isEmpty {
                            Text(s3StatusMessage)
                                .font(.footnote)
                                .foregroundColor(s3StatusColor)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("S3 兼容存储")
                        Text("兼容 AWS S3、Cloudflare R2、MinIO、阿里云 OSS、腾讯云 COS 及其他遵循 S3 协议的云存储服务。（图片 ✓，视频 ✓）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
        .formStyle(.grouped)
        .onAppear {
            normalizePickerSelections()
            refreshGDriveStatus()
        }
        .onChange(of: imgbbAPIKey) { value in
            KeychainStore.setString(value, forKey: "upload.imgbb.apiKey", legacyUserDefaultsKey: "imgbbAPIKey")
        }
        .onChange(of: s3AccessKeyID) { value in
            KeychainStore.setString(value, forKey: "upload.s3.accessKeyID", legacyUserDefaultsKey: "s3AccessKeyID")
        }
        .onChange(of: s3SecretAccessKey) { value in
            KeychainStore.setString(value, forKey: "upload.s3.secretAccessKey", legacyUserDefaultsKey: "s3SecretAccessKey")
        }
    }

    // MARK: - Actions

    private func refreshGDriveStatus() {
        gdriveSignedIn = GoogleDriveUploader.shared.isSignedIn
        gdriveEmail = GoogleDriveUploader.shared.userEmail ?? ""
    }

    private func normalizePickerSelections() {
        uploadProvider = normalized(uploadProvider, allowed: ["imgbb", "gdrive", "s3"], fallback: "imgbb")
    }

    private func normalized<T: Equatable>(_ value: T, allowed: [T], fallback: T) -> T {
        allowed.contains(value) ? value : fallback
    }

    private func gdriveSignInAction() {
        gdriveErrorMessage = "" // 清除之前的错误
        NSLog("[Settings] gdriveSignInAction called, isSignedIn: \(GoogleDriveUploader.shared.isSignedIn)")

        if GoogleDriveUploader.shared.isSignedIn {
            NSLog("[Settings] Signing out...")
            GoogleDriveUploader.shared.signOut()
            refreshGDriveStatus()
        } else {
            NSLog("[Settings] Starting sign in...")
            let window = NSApp.windows.first { $0.title == L("macshot Settings") }
            GoogleDriveUploader.shared.signIn(from: window) { [self] success in
                NSLog("[Settings] Sign in completion called with success: \(success)")
                guard success else {
                    NSLog("[Settings] Sign in failed, refreshing status")

                    // 显示详细的错误信息
                    if let error = GoogleDriveUploader.lastSignInError {
                        gdriveErrorMessage = error
                    } else {
                        gdriveErrorMessage = "登录失败，请查看控制台日志了解详情"
                    }
                    refreshGDriveStatus()
                    return
                }
                NSLog("[Settings] Sign in succeeded!")
                gdriveErrorMessage = ""
                window?.makeKeyAndOrderFront(nil)
                gdriveSignedIn = true
                GoogleDriveUploader.shared.fetchUserEmail { [self] in
                    gdriveEmail = GoogleDriveUploader.shared.userEmail ?? ""
                    NSLog("[Settings] Email fetched: \(gdriveEmail)")
                }
            }
        }
    }

    private func s3TestConnection() {
        guard S3Uploader.shared.isConfigured else {
            s3StatusMessage = L("Fill in endpoint, bucket, and credentials first")
            s3StatusColor = .orange
            return
        }

        s3Testing = true
        s3StatusMessage = L("Testing...")
        s3StatusColor = .secondary

        let testData = Data("macshot connection test".utf8)
        let testKey = ".macshot_test_\(UUID().uuidString.prefix(8)).txt"
        S3Uploader.shared.upload(data: testData, filename: testKey, contentType: "text/plain") { result in
            s3Testing = false
            switch result {
            case .success:
                s3StatusMessage = L("Connection successful!")
                s3StatusColor = .green
            case .failure(let error):
                s3StatusMessage = error.localizedDescription
                s3StatusColor = .red
            }
        }
    }
}

// MARK: - Upload History Row

struct UploadHistoryRow: View {
    @AppStorage("uploadProvider") private var uploadProvider = "imgbb"
    @State private var showPopover = false
    @State private var historyCount = 0

    var body: some View {
        HStack(spacing: 12) {
            Text("上传历史")
            Spacer()
            Text(countText)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button("查看") {
                showPopover.toggle()
                loadHistoryCount()
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                UploadHistoryPopoverView()
                    .frame(width: 480, height: 400)
                    .onAppear {
                        loadHistoryCount()
                    }
            }
        }
        .onAppear {
            loadHistoryCount()
        }
    }

    private var countText: String {
        if historyCount == 0 {
            return "暂无记录"
        } else if historyCount == 1 {
            return "1 条记录"
        } else {
            return "\(historyCount) 条记录"
        }
    }

    private func loadHistoryCount() {
        let uploads = UploadHistoryStore.load()
        let filtered = uploads.filter { $0["provider"] == uploadProvider }
        historyCount = filtered.count
    }
}

// MARK: - Upload History Popover View

struct UploadHistoryPopoverView: View {
    @AppStorage("uploadProvider") private var uploadProvider = "imgbb"
    @State private var history: [UploadHistoryItem] = []
    @State private var isLoading = false

    // 固定 5 列网格，间距 2px
    let columns = [GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2)]

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：清空按钮
            HStack {
                Spacer()
                Button(role: .destructive) {
                    clearAllHistory()
                } label: {
                    Text("清空记录")
                }
                .disabled(history.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 网格内容
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
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(history) { item in
                            UploadHistoryCell(item: item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
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
            let uploads = UploadHistoryStore.load()
            let filtered = uploads.filter { $0["provider"] == uploadProvider }

            let items = filtered.map { dict -> UploadHistoryItem in
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
