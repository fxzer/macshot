import Foundation
import CryptoSwift

enum TranslationProvider: String {
    case google = "google"
    case youdao = "youdao"
}

enum TranslationService {

    // MARK: - Provider

    static var provider: TranslationProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "translationProvider"),
               let p = TranslationProvider(rawValue: raw) { return p }
            return .youdao  // Youdao by default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "translationProvider") }
    }

    /// Cached Apple language availability — populated on first check,
    /// reused instantly for subsequent popover opens.
    private static var cachedAppleAvailability: [String: Bool]?

    // MARK: - Youdao Constants

    private enum YoudaoConstants {
        static let baseURL = "https://dict.youdao.com"
        static let client = "fanyideskweb"
        static let product = "webfanyi"
        static let appVersion = "1.0.0"
        static let vendor = "web"
        static let defaultKey = "asdjnjfenknafdfsdfsd"
    }

    /// Cached Youdao key data (secretKey, aesKey, aesIv, expiry)
    /// Protected by cachedYoudaoKeyLock for thread-safe access from URLSession callbacks.
    private static var cachedYoudaoKey: (secretKey: String, aesKey: String, aesIv: String, expiry: Date)?
    private static let cachedYoudaoKeyLock = NSLock()

    // MARK: - Target language

    static var targetLanguage: String {
        get { UserDefaults.standard.string(forKey: "translateTargetLang") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "translateTargetLang") }
    }

    static let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("zh-CN", "Chinese (Simplified)"),
        ("zh-TW", "Chinese (Traditional)"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("nb", "Norwegian"),
        ("uk", "Ukrainian"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("sk", "Slovak"),
        ("bg", "Bulgarian"),
        ("hr", "Croatian"),
        ("id", "Indonesian"),
        ("hi", "Hindi"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
    ]

    // MARK: - Translate a batch of strings (auto-detect source)

    /// Translates multiple strings using the selected provider.
    /// Calls completion on the main queue.
    static func translateBatch(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard !texts.isEmpty else {
            completion(.success([]))
            return
        }

        if provider == .youdao {
            translateBatchYoudao(texts: texts, targetLang: targetLang, completion: completion)
        } else {
            translateBatchGoogle(texts: texts, targetLang: targetLang, completion: completion)
        }
    }

    // MARK: - Google Translate (unofficial endpoint)

    private static func translateBatchGoogle(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        var results = Array(repeating: "", count: texts.count)
        let group = DispatchGroup()
        var firstError: Error?
        let lock = NSLock()

        for (i, text) in texts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results[i] = text
                continue
            }
            group.enter()
            translateOneGoogle(text: trimmed, targetLang: targetLang) { result in
                lock.lock()
                switch result {
                case .success(let translated):
                    results[i] = translated
                case .failure(let error):
                    if firstError == nil { firstError = error }
                    results[i] = ""
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
    }

    private static func translateOneGoogle(
        text: String,
        targetLang: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl",     value: "auto"),
            URLQueryItem(name: "tl",     value: targetLang),
            URLQueryItem(name: "dt",     value: "t"),
            URLQueryItem(name: "q",      value: text),
        ]
        guard let url = components.url else {
            completion(.failure(TranslationError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(TranslationError.noData))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let outer = json.first as? [[Any]] else {
                completion(.failure(TranslationError.parseError))
                return
            }
            let translated = outer.compactMap { $0.first as? String }.joined()
            guard !translated.isEmpty else {
                completion(.failure(TranslationError.emptyResult))
                return
            }
            completion(.success(translated))
        }.resume()
    }

    // MARK: - Youdao Translator (unofficial endpoint)

    /// Batch translate using Youdao
    private static func translateBatchYoudao(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        var results = Array(repeating: "", count: texts.count)
        let group = DispatchGroup()
        var firstError: Error?
        let lock = NSLock()

        for (i, text) in texts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results[i] = text
                continue
            }
            group.enter()
            translateOneYoudao(text: trimmed, targetLang: targetLang) { result in
                lock.lock()
                switch result {
                case .success(let translated):
                    results[i] = translated
                case .failure(let error):
                    if firstError == nil { firstError = error }
                    results[i] = ""
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
    }

    /// Translate single text using Youdao
    static func translateOneYoudao(
        text: String,
        targetLang: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Get or refresh Youdao key
        fetchYoudaoKey { result in
            switch result {
            case .success(let (secretKey, aesKey, aesIv)):
                // Map language codes to Youdao format
                guard let youdaoTargetLang = youdaoLanguageCode(from: targetLang) else {
                    completion(.failure(TranslationError.parseError))
                    return
                }

                let timestamp = currentTimestamp()
                let sign = generateYoudaoSign(
                    client: YoudaoConstants.client,
                    timestamp: timestamp,
                    product: YoudaoConstants.product,
                    key: secretKey
                )

                var components = URLComponents(string: "\(YoudaoConstants.baseURL)/webtranslate")!
                components.queryItems = [
                    URLQueryItem(name: "client", value: YoudaoConstants.client),
                    URLQueryItem(name: "product", value: YoudaoConstants.product),
                    URLQueryItem(name: "appVersion", value: YoudaoConstants.appVersion),
                    URLQueryItem(name: "vendor", value: YoudaoConstants.vendor),
                    URLQueryItem(name: "pointParam", value: "client,mysticTime,product"),
                    URLQueryItem(name: "keyfrom", value: "fanyi.web"),
                    URLQueryItem(name: "keyid", value: "webfanyi"),
                    URLQueryItem(name: "sign", value: sign),
                    URLQueryItem(name: "mysticTime", value: timestamp),
                    URLQueryItem(name: "from", value: "auto"),
                    URLQueryItem(name: "to", value: youdaoTargetLang),
                    URLQueryItem(name: "dictResult", value: "false"),
                    URLQueryItem(name: "i", value: text),
                ]

                guard let url = components.url else {
                    completion(.failure(TranslationError.badURL))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")
                request.setValue("OUTFOX_SEARCH_USER_ID=1796239350@10.110.96.157;", forHTTPHeaderField: "Cookie")
                request.timeoutInterval = 15

                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    guard let data = data,
                          let encryptedText = String(data: data, encoding: .utf8) else {
                        completion(.failure(TranslationError.noData))
                        return
                    }

                    // Decrypt response
                    guard let decryptedText = decryptYoudaoResponse(
                        encryptedText: encryptedText,
                        key: aesKey,
                        iv: aesIv
                    ),
                    let decryptedData = decryptedText.data(using: .utf8) else {
                        completion(.failure(TranslationError.parseError))
                        return
                    }

                    // Parse JSON
                    do {
                        let youdaoResponse = try JSONDecoder().decode(YoudaoTranslateResponse.self, from: decryptedData)
                        if youdaoResponse.code == 0 {
                            // Flatten the nested arrays and join translations
                            let translations = youdaoResponse.translateResult.map { group in
                                group.map { $0.tgt }.joined(separator: "")
                            }
                            let translatedText = translations.joined(separator: "")
                            completion(.success(translatedText))
                        } else {
                            completion(.failure(TranslationError.parseError))
                        }
                    } catch {
                        completion(.failure(TranslationError.parseError))
                    }
                }.resume()

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Fetch Youdao translation key from the web API
    static func fetchYoudaoKey(
        completion: @escaping (Result<(secretKey: String, aesKey: String, aesIv: String), Error>) -> Void
    ) {
        // Check cache first (thread-safe)
        cachedYoudaoKeyLock.lock()
        if let cached = cachedYoudaoKey, cached.expiry > Date() {
            let result = (cached.secretKey, cached.aesKey, cached.aesIv)
            cachedYoudaoKeyLock.unlock()
            completion(.success(result))
            return
        }
        cachedYoudaoKeyLock.unlock()

        let timestamp = currentTimestamp()
        let sign = generateYoudaoSign(
            client: YoudaoConstants.client,
            timestamp: timestamp,
            product: YoudaoConstants.product,
            key: YoudaoConstants.defaultKey
        )

        var components = URLComponents(string: "\(YoudaoConstants.baseURL)/webtranslate/key")!
        components.queryItems = [
            URLQueryItem(name: "client", value: YoudaoConstants.client),
            URLQueryItem(name: "product", value: YoudaoConstants.product),
            URLQueryItem(name: "appVersion", value: YoudaoConstants.appVersion),
            URLQueryItem(name: "vendor", value: YoudaoConstants.vendor),
            URLQueryItem(name: "pointParam", value: "client,mysticTime,product"),
            URLQueryItem(name: "keyfrom", value: "fanyi.web"),
            URLQueryItem(name: "keyid", value: "webfanyi-key-getter"),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "mysticTime", value: timestamp),
        ]

        guard let url = components.url else {
            completion(.failure(TranslationError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(TranslationError.noData))
                return
            }

            do {
                let youdaoKey = try JSONDecoder().decode(YoudaoKey.self, from: data)
                if youdaoKey.code == 0 {
                    // Cache for 10 minutes (thread-safe)
                    cachedYoudaoKeyLock.lock()
                    cachedYoudaoKey = (
                        secretKey: youdaoKey.data.secretKey,
                        aesKey: youdaoKey.data.aesKey,
                        aesIv: youdaoKey.data.aesIv,
                        expiry: Date().addingTimeInterval(600)
                    )
                    cachedYoudaoKeyLock.unlock()
                    completion(.success((youdaoKey.data.secretKey, youdaoKey.data.aesKey, youdaoKey.data.aesIv)))
                } else {
                    completion(.failure(TranslationError.parseError))
                }
            } catch {
                completion(.failure(TranslationError.parseError))
            }
        }.resume()
    }

    /// Generate MD5 sign for Youdao API
    static func generateYoudaoSign(
        client: String,
        timestamp: String,
        product: String,
        key: String
    ) -> String {
        let signText = "client=\(client)&mysticTime=\(timestamp)&product=\(product)&key=\(key)"
        guard let data = signText.data(using: .utf8) else { return "" }
        do {
            let hash = try Digest.md5(data.bytes)
            return hash.toHexString()
        } catch {
            return ""
        }
    }

    /// Decrypt Youdao AES-128-CBC response
    static func decryptYoudaoResponse(
        encryptedText: String,
        key: String,
        iv: String
    ) -> String? {
        // Convert URL-safe base64 to standard base64
        let standardBase64 = encryptedText
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Decode base64 string to data
        guard let encryptedData = Data(base64Encoded: standardBase64) else {
            return nil
        }

        // Generate MD5 hashes for key and iv using CryptoSwift
        guard let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8) else {
            return nil
        }

        do {
            // Use CryptoSwift's MD5
            let keyHash = try Digest.md5(keyData.bytes)
            let ivHash = try Digest.md5(ivData.bytes)

            // Create AES cipher with CBC mode and PKCS7 padding
            let aes = try AES(
                key: keyHash,
                blockMode: CBC(iv: ivHash),
                padding: .pkcs7
            )

            // Decrypt the data
            let decryptedBytes = try aes.decrypt(encryptedData.bytes)

            // Convert decrypted bytes to string
            return String(data: Data(decryptedBytes), encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Map language codes to Youdao format
    static func youdaoLanguageCode(from code: String) -> String? {
        switch code {
        case "zh-CN": return "zh-CHS"
        case "zh-TW": return "zh-CHT"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "es": return "es"
        case "pt": return "pt"
        case "it": return "it"
        case "de": return "de"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "nl": return "nl"
        case "id": return "id"
        case "vi": return "vi"
        default: return nil
        }
    }

    /// A timestamp string in milliseconds
    static func currentTimestamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }
}

enum TranslationError: LocalizedError {
    case badURL, noData, parseError, emptyResult
    var errorDescription: String? {
        switch self {
        case .badURL:      return "Invalid translation URL"
        case .noData:      return "No response from translation service"
        case .parseError:  return "Could not parse translation response"
        case .emptyResult: return "Translation returned empty result"
        }
    }
}
