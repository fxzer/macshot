import SwiftUI

struct UploadsSettingsView: View {

    // Provider
    @AppStorage("uploadProvider") private var uploadProvider = "imgbb"

    // imgbb
    @AppStorage("imgbbAPIKey") private var imgbbAPIKey = ""

    // S3 fields
    @AppStorage("s3Endpoint") private var s3Endpoint = ""
    @AppStorage("s3Region") private var s3Region = "auto"
    @AppStorage("s3Bucket") private var s3Bucket = ""
    @AppStorage("s3AccessKeyID") private var s3AccessKeyID = ""
    @AppStorage("s3SecretAccessKey") private var s3SecretAccessKey = ""
    @AppStorage("s3PublicURLBase") private var s3PublicURLBase = ""
    @AppStorage("s3PathPrefix") private var s3PathPrefix = ""

    // Google Drive state
    @State private var gdriveEmail: String = ""
    @State private var gdriveSignedIn: Bool = false

    // S3 test state
    @State private var s3Testing = false
    @State private var s3StatusMessage = ""
    @State private var s3StatusColor: Color = .secondary

    // Upload history
    @State private var uploads: [[String: String]] = []

    var body: some View {
        Form {
            // MARK: - Upload Provider
            Section {
                Picker(L("Provider"), selection: $uploadProvider) {
                    Text(L("imgbb (images only)")).tag("imgbb")
                    Text(L("Google Drive (images + videos)")).tag("gdrive")
                    Text(L("S3-Compatible (images + videos)")).tag("s3")
                }
            } header: {
                Text(L("Upload Provider"))
            }

            // MARK: - Google Drive
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
            } header: {
                Text(L("Google Drive"))
            } footer: {
                Text(L("Files are uploaded to a \"macshot\" folder in your Google Drive. Everything stays private — nothing is shared publicly."))
            }

            // MARK: - S3-Compatible
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
                    Button(L("Test Connection")) {
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
                Text(L("S3-Compatible Storage"))
            } footer: {
                Text(L("Works with AWS S3, Cloudflare R2, MinIO, DigitalOcean Spaces, Backblaze B2, and other S3-compatible services. Supports images and videos."))
            }

            // MARK: - imgbb
            Section {
                TextField(L("API key"), text: $imgbbAPIKey, prompt: Text(L("Leave empty to use default")))
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("imgbb")
            } footer: {
                Text(L("A shared key is included — get your own free key at imgbb.com/api if you hit rate limits. Images only (no video support)."))
            }

            // MARK: - Upload History
            Section {
                if uploads.isEmpty {
                    Text(L("No uploads yet."))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(uploads.enumerated()), id: \.offset) { index, upload in
                        VStack(alignment: .leading, spacing: 4) {
                            if let link = upload["link"] {
                                uploadRow(tag: "URL", value: link)
                            }
                            if let deleteURL = upload["deleteURL"], !deleteURL.isEmpty {
                                uploadRow(tag: "DEL", value: deleteURL)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text(L("Upload History"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshGDriveStatus()
            loadUploads()
        }
    }

    // MARK: - Upload Row

    @ViewBuilder
    private func uploadRow(tag: String, value: String) -> some View {
        HStack {
            Text(tag)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(tag == "URL" ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(L("Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    private func refreshGDriveStatus() {
        gdriveSignedIn = GoogleDriveUploader.shared.isSignedIn
        gdriveEmail = GoogleDriveUploader.shared.userEmail ?? ""
    }

    private func gdriveSignInAction() {
        if GoogleDriveUploader.shared.isSignedIn {
            GoogleDriveUploader.shared.signOut()
            refreshGDriveStatus()
        } else {
            // Find the settings window
            let window = NSApp.windows.first { $0.title == L("macshot Settings") }
            GoogleDriveUploader.shared.signIn(from: window) { [self] success in
                guard success else {
                    refreshGDriveStatus()
                    return
                }
                window?.makeKeyAndOrderFront(nil)
                gdriveSignedIn = true
                GoogleDriveUploader.shared.fetchUserEmail { [self] in
                    gdriveEmail = GoogleDriveUploader.shared.userEmail ?? ""
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

    private func loadUploads() {
        uploads = ((UserDefaults.standard.array(forKey: "imgbbUploads") as? [[String: String]]) ?? []).reversed()
    }
}
