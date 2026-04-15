//
//  YoudaoModels.swift
//  macshot
//
//  有道翻译数据模型
//

import Foundation

// MARK: - YoudaoTranslateResponse

/// 有道翻译响应模型
struct YoudaoTranslateResponse: Codable {
    struct TranslateResultItem: Codable {
        let src: String
        let tgt: String
        let tgtPronounce: String?
        let srcPronounce: String?
    }

    let translateResult: [[TranslateResultItem]]
    let type: String // 例如: "en2zh-CHS"
    let code: Int
}

// MARK: - YoudaoKey

/// 有道密钥响应模型
struct YoudaoKey: Codable {
    struct DataClass: Codable {
        let secretKey: String
        let aesKey: String
        let aesIv: String
    }

    let data: DataClass
    let code: Int
    let msg: String
}
