import Cocoa

final class SMMSUploader {

    static let shared = SMMSUploader()
    private let tokenKeychainKey = "upload.smms.apiToken"

    private let endpoint = URL(string: "https://smms.app/api/v2/upload")!

    var apiToken: String {
        KeychainStore.string(forKey: tokenKeychainKey, legacyUserDefaultsKey: "smmsAPIToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func upload(image: NSImage, completion: @escaping (Result<ImageUploadResult, Error>) -> Void) {
        guard !apiToken.isEmpty else {
            completion(.failure(Self.error("Enter your SM.MS token in Settings")))
            return
        }

        guard let pngData = pngData(from: image) else {
            completion(.failure(Self.error("Failed to encode image")))
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiToken, forHTTPHeaderField: "Authorization")
        request.httpBody = multipartBody(data: pngData, filename: "Screenshot-\(Self.timestamp()).png", boundary: boundary)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(Self.error("No response data")))
                }
                return
            }

            do {
                let payload = try JSONDecoder().decode(Response.self, from: data)
                if payload.success,
                   let uploadData = payload.data,
                   let link = uploadData.url, !link.isEmpty {
                    let deleteValue = uploadData.delete ?? uploadData.hash ?? ""
                    DispatchQueue.main.async {
                        completion(.success(ImageUploadResult(link: link, deleteURL: deleteValue)))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.failure(Self.error(payload.message ?? payload.images ?? "SM.MS upload failed")))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(Self.error("Failed to parse SM.MS response")))
                }
            }
        }.resume()
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func multipartBody(data: Data, filename: String, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"smfile\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func error(_ description: String) -> NSError {
        NSError(domain: "SMMSUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}

private extension SMMSUploader {
    struct Response: Decodable {
        let success: Bool
        let message: String?
        let images: String?
        let data: UploadData?
    }

    struct UploadData: Decodable {
        let url: String?
        let delete: String?
        let hash: String?
    }
}
