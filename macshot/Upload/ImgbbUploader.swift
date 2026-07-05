import Cocoa

struct ImageUploadResult {
    let link: String
    let deleteURL: String
}

enum ImageUploader {

    private static let keychainKey = "upload.imgbb.apiKey"

    static var apiKey: String? {
        guard let key = KeychainStore.string(forKey: keychainKey, legacyUserDefaultsKey: "imgbbAPIKey"),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func upload(image: NSImage, completion: @escaping (Result<ImageUploadResult, Error>) -> Void) {
        func finish(_ result: Result<ImageUploadResult, Error>) {
            DispatchQueue.main.async {
                completion(result)
            }
        }

        guard let key = apiKey else {
            finish(.failure(NSError(domain: "ImageUploader", code: 5, userInfo: [NSLocalizedDescriptionKey: L("ImgBB API key not configured. Please add your API key in Settings.")])))
            return
        }

        // PNG-encode via the shared ImageEncoder path (CGImageDestination) —
        // avoids the expensive NSImage→TIFF→NSBitmapImageRep→CGImage round-trip.
        // imgbb accepts PNG/JPEG; we always send PNG to preserve transparency.
        guard let pngData = ImageEncoder.encodePNG(image) else {
            finish(.failure(NSError(domain: "ImageUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])))
            return
        }

        let base64String = pngData.base64EncodedString()

        let urlString = "https://api.imgbb.com/1/upload?key=\(key)"
        guard let url = URL(string: urlString) else {
            finish(.failure(NSError(domain: "ImageUploader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        // Build multipart form body
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // image field (base64)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"\r\n\r\n".data(using: .utf8)!)
        body.append(base64String.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                finish(.failure(error))
                return
            }

            guard let data = data else {
                finish(.failure(NSError(domain: "ImageUploader", code: 3, userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let success = json["success"] as? Bool, success,
                      let dataDict = json["data"] as? [String: Any],
                      let imageURL = dataDict["url"] as? String,
                      let deleteURL = dataDict["delete_url"] as? String else {
                    // Try to extract error message
                    let errorMsg: String
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errData = json["error"] as? [String: Any],
                       let msg = errData["message"] as? String {
                        errorMsg = msg
                    } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let status = json["status_code"] as? Int {
                        errorMsg = "API error (status \(status))"
                    } else {
                        errorMsg = "Unknown error"
                    }
                    finish(.failure(NSError(domain: "ImageUploader", code: 4, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    return
                }

                let result = ImageUploadResult(link: imageURL, deleteURL: deleteURL)
                finish(.success(result))
            } catch {
                finish(.failure(error))
            }
        }.resume()
    }

}
