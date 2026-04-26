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

    init() {
        // Load secrets during init to avoid repeated Keychain access
        _imgbbAPIKey = State(initialValue: KeychainStore.string(forKey: "upload.imgbb.apiKey", legacyUserDefaultsKey: "imgbbAPIKey") ?? "")
        _s3AccessKeyID = State(initialValue: KeychainStore.string(forKey: "upload.s3.accessKeyID", legacyUserDefaultsKey: "s3AccessKeyID") ?? "")
        _s3SecretAccessKey = State(initialValue: KeychainStore.string(forKey: "upload.s3.secretAccessKey", legacyUserDefaultsKey: "s3SecretAccessKey") ?? "")
    }

    private var imgbbAPIKeyBinding: Binding<String> {
        Binding(
            get: { imgbbAPIKey },
            set: { value in
                imgbbAPIKey = value
                KeychainStore.setString(value, forKey: "upload.imgbb.apiKey", legacyUserDefaultsKey: "imgbbAPIKey")
            }
        )
    }

    private var s3AccessKeyIDBinding: Binding<String> {
        Binding(
            get: { s3AccessKeyID },
            set: { value in
                s3AccessKeyID = value
                KeychainStore.setString(value, forKey: "upload.s3.accessKeyID", legacyUserDefaultsKey: "s3AccessKeyID")
            }
        )
    }

    private var s3SecretAccessKeyBinding: Binding<String> {
        Binding(
            get: { s3SecretAccessKey },
            set: { value in
                s3SecretAccessKey = value
                KeychainStore.setString(value, forKey: "upload.s3.secretAccessKey", legacyUserDefaultsKey: "s3SecretAccessKey")
            }
        )
    }

    private var isS3TestAvailable: Bool {
        !s3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !s3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !s3AccessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !s3SecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        Text(L("S3 Compatible Storage")).tag("s3")
                    }
                    UploadHistoryRow()
                } header: {
                    Text(L("Upload Service"))
                }

                // MARK: - Service Configuration (dynamic)
                if uploadProvider == "imgbb" {
                    Section {
                        TextField(L("API key"), text: imgbbAPIKeyBinding, prompt: Text(L("Paste your API key")))
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
                        TextField(L("Access Key"), text: s3AccessKeyIDBinding, prompt: Text("AKIAIOSFODNN7EXAMPLE"))
                            .font(.system(.body, design: .monospaced))
                        TextField(L("Secret Key"), text: s3SecretAccessKeyBinding, prompt: Text("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"))
                            .font(.system(.body, design: .monospaced))
                        TextField(L("Public URL"), text: $s3PublicURLBase, prompt: Text("https://cdn.example.com"))
                            .font(.system(.body, design: .monospaced))
                        TextField(L("Path Prefix"), text: $s3PathPrefix, prompt: Text("screenshots/"))
                            .font(.system(.body, design: .monospaced))
                        S3ConnectionTestRow(testing: $s3Testing, isAvailable: isS3TestAvailable) {
                            s3TestConnection()
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("S3 Compatible Storage"))
                            Text(L("Compatible with AWS S3, Cloudflare R2, MinIO, Alibaba Cloud OSS, Tencent Cloud COS, and other S3-compatible storage services. (Images ✓, Videos ✓)"))
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
                        gdriveErrorMessage = L("Login failed. Check the console log for details.")
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
            showAlert(title: L("S3 Test"), message: L("Fill in endpoint, bucket, and credentials first."))
            return
        }

        s3Testing = true

        let testData = Data("macshot connection test".utf8)
        let testKey = ".macshot_test_\(UUID().uuidString.prefix(8)).txt"
        S3Uploader.shared.upload(data: testData, filename: testKey, contentType: "text/plain") { result in
            s3Testing = false
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showAlert(title: L("S3 Test"), message: L("Connection successful!"))
                case .failure(let error):
                    showAlert(title: L("S3 Test Failed"), message: error.localizedDescription)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }
}

// MARK: - S3 Connection Test Row

struct S3ConnectionTestRow: View {
    @Binding var testing: Bool
    let isAvailable: Bool
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Connection Test"))
            Spacer()
            Button(testing ? L("Testing...") : L("Test")) {
                onTest()
            }
            .disabled(testing || !isAvailable)
        }
    }
}

// MARK: - Upload History Row

struct UploadHistoryRow: View {
    @AppStorage("uploadProvider") private var uploadProvider = "imgbb"
    @State private var showPopover = false
    @ObservedObject private var historyStore = UploadHistoryStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Upload History"))
            Spacer()
            Text(countText)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button(L("View")) {
                showPopover.toggle()
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                UploadHistoryPopoverView()
                    .frame(width: 480, height: 400)
            }
        }
    }

    private var countText: String {
        let count = historyStore.count(for: uploadProvider)
        if count == 0 {
            return L("No records")
        } else {
            return String(format: L("%d records"), count)
        }
    }
}

// MARK: - Upload History Popover View

struct UploadHistoryPopoverView: View {
    @AppStorage("uploadProvider") private var uploadProvider = "imgbb"
    @ObservedObject private var historyStore = UploadHistoryStore.shared
    @State private var history: [UploadHistoryItem] = []

    // 固定 5 列网格，间距 2px
    let columns = [GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2),
                   GridItem(.flexible(), spacing: 2)]

    var body: some View {
        VStack(spacing: 0) {
            // 头部：服务商名 + 清空按钮
            HStack {
                Text(providerDisplayName)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    clearAllHistory()
                } label: {
                    Text(L("Clear History"))
                }
                .disabled(history.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            // 网格内容
            if history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L("No uploads yet."))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(history) { item in
                            UploadHistoryCell(item: item)
                                .padding(.bottom, 8)
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
        .onChange(of: historyStore.history) { _ in
            loadHistory()
        }
    }

    private var providerDisplayName: String {
        switch uploadProvider {
        case "imgbb": return "ImgBB"
        case "gdrive": return "Google Drive"
        case "s3": return L("S3 Compatible Storage")
        default: return uploadProvider
        }
    }

    private func loadHistory() {
        let filtered = historyStore.history.filter { $0["provider"] == uploadProvider }
        history = filtered.map { dict -> UploadHistoryItem in
            let id = dict["id"] ?? UUID().uuidString
            return UploadHistoryItem(
                id: id,
                provider: dict["provider"] ?? "unknown",
                link: dict["link"] ?? "",
                deleteURL: dict["deleteURL"] ?? "",
                timestamp: Date()
            )
        }
    }

    private func clearAllHistory() {
        // 只清除当前服务商的上传历史
        UploadHistoryStore.clear(provider: uploadProvider)
    }
}
