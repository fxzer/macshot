import Cocoa
import UniformTypeIdentifiers

/// Uploader for self-hosted CloudFlare-ImgBed deployments
/// (https://github.com/MarSeventh/CloudFlare-ImgBed).
///
/// Auth: API Token (Bearer). Tokens are created in the admin panel; the
/// `upload` permission is required for uploads.
final class CloudflareImgBedUploader {

    static let shared = CloudflareImgBedUploader()
    private let tokenKeychainKey = "upload.cfimgbed.apiToken"

    // MARK: - Configuration

    struct Config {
        let endpoint: String       // e.g. "https://imgbed.example.com" (no /upload)
        let apiToken: String
        let uploadChannel: String  // "" = backend default
        let channelName: String
        let uploadFolder: String

        var isValid: Bool {
            !endpoint.isEmpty && !apiToken.isEmpty
        }
    }

    var config: Config {
        let ud = UserDefaults.standard
        let endpoint = (ud.string(forKey: "cfimgbedEndpoint") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Config(
            endpoint: endpoint,
            apiToken: KeychainStore.string(forKey: tokenKeychainKey) ?? "",
            uploadChannel: ud.string(forKey: "cfimgbedUploadChannel") ?? "",
            channelName: ud.string(forKey: "cfimgbedChannelName") ?? "",
            uploadFolder: ud.string(forKey: "cfimgbedUploadFolder") ?? ""
        )
    }

    var isConfigured: Bool { config.isValid }

    // MARK: - Upload Image

    func uploadImage(
        _ image: NSImage,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let data = ImageEncoder.encode(image) else {
            completion(.failure(CFImgBedError.encodingFailed))
            return
        }
        let ext = ImageEncoder.fileExtension
        let mime = ImageEncoder.utType.preferredMIMEType ?? "application/octet-stream"
        let filename = FilenameTemplateEngine.makeFilename(kind: .screenshot, fileExtension: ext)
        upload(data: data, filename: filename, contentType: mime, progress: progress, completion: completion)
    }

    // MARK: - Core Upload

    func upload(
        data: Data,
        filename: String,
        contentType: String,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let cfg = config
        guard cfg.isValid else {
            completion(.failure(CFImgBedError.notConfigured))
            return
        }
        guard let uploadURL = makeUploadURL(cfg: cfg) else {
            completion(.failure(CFImgBedError.invalidEndpoint))
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cfg.apiToken)", forHTTPHeaderField: "Authorization")

        let safeFilename = filename.replacingOccurrences(of: "\"", with: "_")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let task = URLSession.shared.uploadTask(with: request, from: body) { responseData, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(CFImgBedError.noResponse)) }
                return
            }
            let bodyString = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            guard (200...299).contains(httpResponse.statusCode) else {
                let msg = bodyString.isEmpty ? "HTTP \(httpResponse.statusCode)" : bodyString
                DispatchQueue.main.async {
                    completion(.failure(CFImgBedError.httpError(httpResponse.statusCode, msg)))
                }
                return
            }
            guard let data = responseData,
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let src = array.first?["src"] as? String,
                  !src.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(CFImgBedError.parseFailed(bodyString)))
                }
                return
            }
            let finalLink = Self.absoluteLink(src: src, endpoint: cfg.endpoint)
            DispatchQueue.main.async { completion(.success(finalLink)) }
        }

        if let progress {
            let observation = task.progress.observe(\.fractionCompleted) { observedProgress, _ in
                DispatchQueue.main.async { progress(observedProgress.fractionCompleted) }
            }
            objc_setAssociatedObject(task, &Self.progressObservationKey, observation, .OBJC_ASSOCIATION_RETAIN)
        }
        task.resume()
    }

    private static var progressObservationKey: UInt8 = 0

    // MARK: - URL builder

    private func makeUploadURL(cfg: Config) -> URL? {
        let base = trimmedEndpoint(cfg.endpoint)
        var components = URLComponents(string: "\(base)/upload")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "returnFormat", value: "full"),
            URLQueryItem(name: "autoRetry", value: "true")
        ]
        if !cfg.uploadChannel.isEmpty {
            items.append(URLQueryItem(name: "uploadChannel", value: cfg.uploadChannel))
        }
        if !cfg.channelName.isEmpty {
            items.append(URLQueryItem(name: "channelName", value: cfg.channelName))
        }
        if !cfg.uploadFolder.isEmpty {
            items.append(URLQueryItem(name: "uploadFolder", value: cfg.uploadFolder))
        }
        components?.queryItems = items
        return components?.url
    }

    private func trimmedEndpoint(_ endpoint: String) -> String {
        endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
    }

    private static func absoluteLink(src: String, endpoint: String) -> String {
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            return src
        }
        let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let path = src.hasPrefix("/") ? src : "/\(src)"
        return base + path
    }

    // MARK: - Errors

    enum CFImgBedError: LocalizedError {
        case notConfigured
        case invalidEndpoint
        case encodingFailed
        case fileReadFailed
        case noResponse
        case parseFailed(String)
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return L("CloudFlare ImgBed not configured — check Settings")
            case .invalidEndpoint:
                return L("Invalid CloudFlare ImgBed endpoint URL")
            case .encodingFailed:
                return L("Failed to encode image")
            case .fileReadFailed:
                return L("Failed to read file")
            case .noResponse:
                return L("No response from server")
            case .parseFailed(let raw):
                return String(format: L("Unexpected response: %@"), raw)
            case .httpError(let code, let msg):
                return String(format: L("CloudFlare ImgBed error (%d): %@"), code, msg)
            }
        }
    }
}
