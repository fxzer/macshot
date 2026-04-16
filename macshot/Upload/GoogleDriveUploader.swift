import Cocoa
import Security
import CryptoKit
import AuthenticationServices

/// Google Drive uploader using OAuth2 with PKCE.
/// Files are uploaded to a "macshot" folder in the user's Drive, kept private (not shared).
final class GoogleDriveUploader: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = GoogleDriveUploader()
    private let tokenKeychainKey = "upload.gdrive.tokens"

    // Your Google OAuth client ID - create at https://console.cloud.google.com/
    // Application type: Desktop app
    private let clientID = "423880796342-i7u2qecp4oc6ce44l66tdegoc5g931dp.apps.googleusercontent.com"
    /// Reversed client ID used as custom URL scheme for OAuth redirect.
    private var callbackScheme: String {
        clientID.components(separatedBy: ".").reversed().joined(separator: ".")
    }
    /// OAuth scopes for Google Drive access.
    /// Using drive.file scope which is less restrictive and works better with test apps.
    private let scopes = "https://www.googleapis.com/auth/drive.file"

    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let uploadURL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
    private let filesURL = "https://www.googleapis.com/drive/v3/files"

    private var macShotFolderID: String?
    private var authSession: ASWebAuthenticationSession?
    private weak var presentationWindow: NSWindow?

    /// Dedicated session for uploads with longer timeouts to avoid "connection lost" on large files.
    private lazy var uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300   // 5 min per request
        config.timeoutIntervalForResource = 600  // 10 min total
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    var isSignedIn: Bool {
        loadRefreshToken() != nil
    }

    // MARK: - Helpers

    /// Safely create a URL from a string, returning nil on failure.
    private func url(from string: String) -> URL? {
        URL(string: string)
    }

    var userEmail: String? {
        UserDefaults.standard.string(forKey: "gdriveUserEmail")
    }

    /// Last sign-in error message (for display in UI)
    static var lastSignInError: String?

    /// Start the OAuth2 sign-in flow using ASWebAuthenticationSession.
    func signIn(from window: NSWindow?, completion: @escaping (Bool) -> Void) {
        Self.lastSignInError = nil
        NSLog("[GoogleDrive] Starting sign in flow...")
        NSLog("[GoogleDrive] Starting sign in flow...")
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let redirectURI = "\(callbackScheme):/oauthredirect"

        NSLog("[GoogleDrive] Client ID: \(clientID)")
        NSLog("[GoogleDrive] Callback scheme: \(callbackScheme)")
        NSLog("[GoogleDrive] Redirect URI: \(redirectURI)")

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes + " email"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else { completion(false); return }

        presentationWindow = window
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }
            self.authSession = nil

            NSLog("[GoogleDrive] OAuth callback triggered")
            if let error = error {
                let nsError = error as NSError
                NSLog("[GoogleDrive] OAuth error: \(error.localizedDescription)")
                NSLog("[GoogleDrive] Error domain: \(nsError.domain)")
                NSLog("[GoogleDrive] Error code: \(nsError.code)")
                NSLog("[GoogleDrive] Error userInfo: \(nsError.userInfo)")

                // 检查是否是用户取消
                if nsError.domain == "com.apple.AuthenticationServices" && nsError.code == 1 {
                    NSLog("[GoogleDrive] User cancelled authentication")
                    Self.lastSignInError = "用户取消了登录"
                } else {
                    // 其他错误，可能是配置问题
                    let errorMsg = """
                    OAuth 错误: \(error.localizedDescription)
                    错误代码: \(nsError.code)
                    可能原因:
                    1. 未添加测试用户
                    2. OAuth 同意屏幕配置不完整
                    3. URL Scheme 配置错误
                    """
                    Self.lastSignInError = errorMsg
                }

                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let callbackURL = callbackURL,
                  let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                NSLog("[GoogleDrive] Failed to extract auth code from callback")
                if let callbackURL = callbackURL {
                    NSLog("[GoogleDrive] Callback URL: \(callbackURL.absoluteString)")
                }
                DispatchQueue.main.async { completion(false) }
                return
            }

            NSLog("[GoogleDrive] Auth code received, exchanging for token...")
            self.exchangeCodeWithRedirect(code, codeVerifier: codeVerifier, redirectURI: redirectURI, completion: completion)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationWindow ?? NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    func signOut() {
        deleteTokens()
        UserDefaults.standard.removeObject(forKey: "gdriveUserEmail")
        macShotFolderID = nil
    }

    /// Progress callback: percentage 0.0–1.0
    var onProgress: ((Double) -> Void)?

    /// Upload a file (image or video) to the macshot folder.
    func upload(data: Data, filename: String, mimeType: String, completion: @escaping (Result<String, Error>) -> Void) {
        ensureValidToken { [weak self] success in
            guard let self = self, success else {
                completion(.failure(Self.error("Not signed in")))
                return
            }
            self.ensureMacShotFolder { result in
                switch result {
                case .success(let folderID):
                    self.uploadFile(data: data, filename: filename, mimeType: mimeType, folderID: folderID, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Upload an NSImage.
    func uploadImage(_ image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            completion(.failure(Self.error("Failed to encode image")))
            return
        }
        let filename = "Screenshot \(Self.timestamp()).png"
        upload(data: pngData, filename: filename, mimeType: "image/png", completion: completion)
    }

    /// Upload a video file from URL.
    func uploadVideo(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let ext = url.pathExtension.lowercased()
        let mime = ext == "gif" ? "image/gif" : "video/mp4"
        let filename = url.lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url) else {
                DispatchQueue.main.async {
                    completion(.failure(Self.error("Failed to read video file")))
                }
                return
            }
            self?.upload(data: data, filename: filename, mimeType: mime, completion: completion)
        }
    }

    // MARK: - OAuth Token Exchange

    private func exchangeCodeWithRedirect(_ code: String, codeVerifier: String, redirectURI: String, completion: @escaping (Bool) -> Void) {
        NSLog("[GoogleDrive] Exchanging auth code for token...")
        guard let tokenURL = url(from: tokenURL) else {
            NSLog("[GoogleDrive] Invalid token URL")
            completion(false)
            return
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ].compactMap { key, value in
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return "\(key)=\(encoded)"
            }
            return nil
        }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("[GoogleDrive] Token exchange error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[GoogleDrive] Token exchange response status: \(statusCode)")

            guard let data = data else {
                NSLog("[GoogleDrive] No data in token response")
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                NSLog("[GoogleDrive] Token response: \(responseString)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("[GoogleDrive] Failed to parse token response")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let accessToken = json["access_token"] as? String else {
                NSLog("[GoogleDrive] No access_token in response")
                DispatchQueue.main.async { completion(false) }
                return
            }

            NSLog("[GoogleDrive] Access token received successfully")

            let refreshToken = json["refresh_token"] as? String ?? self.loadRefreshToken()
            guard let finalRefreshToken = refreshToken else {
                NSLog("[GoogleDrive] No refresh token available")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let expiresIn = json["expires_in"] as? Int ?? 3600
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))

            self.saveToken(accessToken: accessToken, refreshToken: finalRefreshToken, expiry: expiry.timeIntervalSince1970)

            self.fetchUserEmail(accessToken: accessToken)

            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                completion(true)
            }
        }.resume()
    }

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = loadRefreshToken() else {
            completion(false)
            return
        }
        guard let tokenURL = url(from: tokenURL) else {
            completion(false)
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ].compactMap { key, value in
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return "\(key)=\(encoded)"
            }
            return nil
        }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let expiresIn = json["expires_in"] as? Int ?? 3600
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))

            var tokens = self.loadTokens()
            tokens.accessToken = accessToken
            tokens.expiry = expiry.timeIntervalSince1970
            self.saveTokens(tokens)

            DispatchQueue.main.async { completion(true) }
        }.resume()
    }

    private func ensureValidToken(completion: @escaping (Bool) -> Void) {
        guard let expiry = loadExpiry() else {
            completion(false)
            return
        }

        if Date().timeIntervalSince1970 < expiry, loadAccessToken() != nil {
            completion(true)
        } else {
            refreshAccessToken(completion: completion)
        }
    }

    func fetchUserEmail(accessToken: String? = nil, completion: (() -> Void)? = nil) {
        let token = accessToken ?? loadAccessToken()
        guard let token = token else { completion?(); return }
        guard let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else {
            completion?()
            return
        }
        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(email, forKey: "gdriveUserEmail")
                    completion?()
                }
            } else {
                DispatchQueue.main.async { completion?() }
            }
        }.resume()
    }

    // MARK: - Drive Operations

    private func ensureMacShotFolder(completion: @escaping (Result<String, Error>) -> Void) {
        if let id = macShotFolderID { completion(.success(id)); return }

        guard let token = loadAccessToken() else {
            completion(.failure(Self.error("No access token")))
            return
        }

        // Search for existing macshot folder
        let query = "name='macshot' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        var searchURL = URLComponents(string: filesURL)!
        searchURL.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "fields", value: "files(id)")]

        var request = URLRequest(url: searchURL.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(Self.error("Folder search failed: \(error.localizedDescription)"))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(Self.error("Folder search returned no data"))) }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(.failure(Self.error("Folder search: invalid response (HTTP \(statusCode))"))) }
                return
            }

            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                DispatchQueue.main.async { completion(.failure(Self.error("Folder search: \(message) (HTTP \(statusCode))"))) }
                return
            }

            guard let files = json["files"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion(.failure(Self.error("Folder search: unexpected response format (HTTP \(statusCode))"))) }
                return
            }

            if let existing = files.first, let id = existing["id"] as? String {
                self.macShotFolderID = id
                DispatchQueue.main.async { completion(.success(id)) }
            } else {
                self.createMacShotFolder(token: token, completion: completion)
            }
        }.resume()
    }

    private func createMacShotFolder(token: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let filesURL = url(from: filesURL) else {
            completion(.failure(Self.error("Invalid files URL")))
            return
        }
        var request = URLRequest(url: filesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let metadata: [String: Any] = [
            "name": "macshot",
            "mimeType": "application/vnd.google-apps.folder",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: metadata)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(Self.error("Create folder failed: \(error.localizedDescription)"))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(Self.error("Create folder returned no data"))) }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(.failure(Self.error("Create folder: invalid response (HTTP \(statusCode))"))) }
                return
            }

            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                DispatchQueue.main.async { completion(.failure(Self.error("Create folder: \(message) (HTTP \(statusCode))"))) }
                return
            }

            guard let id = json["id"] as? String else {
                DispatchQueue.main.async { completion(.failure(Self.error("Create folder: missing folder ID in response (HTTP \(statusCode))"))) }
                return
            }
            self?.macShotFolderID = id
            DispatchQueue.main.async { completion(.success(id)) }
        }.resume()
    }

    private func uploadFile(data: Data, filename: String, mimeType: String, folderID: String, completion: @escaping (Result<String, Error>) -> Void) {
        uploadFileWithRetry(data: data, filename: filename, mimeType: mimeType, folderID: folderID, attempt: 1, completion: completion)
    }

    private func uploadFileWithRetry(data fileData: Data, filename: String, mimeType: String, folderID: String, attempt: Int, completion: @escaping (Result<String, Error>) -> Void) {
        guard let token = loadAccessToken() else {
            completion(.failure(Self.error("No access token")))
            return
        }

        let boundary = UUID().uuidString
        guard let uploadURL = URL(string: uploadURL) else {
            completion(.failure(Self.error("Invalid upload URL")))
            return
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadata: [String: Any] = [
            "name": filename,
            "parents": [folderID],
        ]
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata) else {
            completion(.failure(Self.error("Failed to serialize metadata")))
            return
        }

        var body = Data()
        // Helper to safely append string data
        func appendString(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        appendString("--\(boundary)\r\n")
        appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadataData)
        appendString("\r\n--\(boundary)\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        appendString("\r\n--\(boundary)--\r\n")

        // Write body to temp file for uploadTask (enables progress tracking)
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("macshot_upload_\(UUID().uuidString).tmp")
        do {
            try body.write(to: tmpFile)
        } catch {
            completion(.failure(error))
            return
        }

        let maxRetries = 3
        let task = uploadSession.uploadTask(with: request, fromFile: tmpFile) { [weak self] data, response, error in
            try? FileManager.default.removeItem(at: tmpFile)

            // Retry on transient network errors
            if let error = error as? URLError,
               [.networkConnectionLost, .timedOut, .notConnectedToInternet].contains(error.code),
               attempt < maxRetries {
                let delay = Double(attempt) * 2.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.uploadFileWithRetry(data: fileData, filename: filename, mimeType: mimeType,
                                              folderID: folderID, attempt: attempt + 1, completion: completion)
                }
                return
            }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            // Retry on 401 (token expired mid-upload) — refresh token and try again
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401, attempt < maxRetries {
                self?.refreshAccessToken { success in
                    guard success else {
                        completion(.failure(Self.error("Authentication expired")))
                        return
                    }
                    self?.uploadFileWithRetry(data: fileData, filename: filename, mimeType: mimeType,
                                              folderID: folderID, attempt: attempt + 1, completion: completion)
                }
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(Self.error("Upload returned no data (HTTP \(statusCode))"))) }
                return
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let apiError = json?["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                DispatchQueue.main.async { completion(.failure(Self.error("Upload: \(message) (HTTP \(statusCode))"))) }
                return
            }
            guard let fileID = json?["id"] as? String else {
                DispatchQueue.main.async { completion(.failure(Self.error("Upload failed (HTTP \(statusCode))"))) }
                return
            }
            let viewLink = "https://drive.google.com/file/d/\(fileID)/view"
            DispatchQueue.main.async {
                self?.onProgress = nil
                completion(.success(viewLink))
            }
        }

        // Observe upload progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.onProgress?(progress.fractionCompleted)
            }
        }
        // Store observation to keep it alive; released when task completes
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        task.resume()
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Token Storage

    private struct TokenData: Codable {
        var accessToken: String?
        var refreshToken: String?
        var expiry: Double?
    }

    private var legacyTokenFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.fxzer.macshot")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                      attributes: [.posixPermissions: 0o700])
        }
        return dir.appendingPathComponent("gdrive_tokens.json")
    }

    private func loadTokens() -> TokenData {
        if let data = KeychainStore.data(forKey: tokenKeychainKey),
           let tokens = try? JSONDecoder().decode(TokenData.self, from: data) {
            return tokens
        }
        if let data = try? Data(contentsOf: legacyTokenFileURL),
           let tokens = try? JSONDecoder().decode(TokenData.self, from: data) {
            KeychainStore.setData(data, forKey: tokenKeychainKey)
            try? FileManager.default.removeItem(at: legacyTokenFileURL)
            return tokens
        }
        return TokenData()
    }

    private func saveTokens(_ tokens: TokenData) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        KeychainStore.setData(data, forKey: tokenKeychainKey)
        try? FileManager.default.removeItem(at: legacyTokenFileURL)
    }

    private func deleteTokens() {
        KeychainStore.deleteValue(forKey: tokenKeychainKey)
        try? FileManager.default.removeItem(at: legacyTokenFileURL)
    }

    // Convenience accessors matching the old Keychain API
    private func saveToken(accessToken: String, refreshToken: String, expiry: Double) {
        var tokens = loadTokens()
        tokens.accessToken = accessToken
        tokens.refreshToken = refreshToken
        tokens.expiry = expiry
        saveTokens(tokens)
    }

    private func loadAccessToken() -> String? { loadTokens().accessToken }
    private func loadRefreshToken() -> String? { loadTokens().refreshToken }
    private func loadExpiry() -> Double? { loadTokens().expiry }

    // MARK: - Helpers

    private static func error(_ msg: String) -> NSError {
        NSError(domain: "GoogleDriveUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }
}
