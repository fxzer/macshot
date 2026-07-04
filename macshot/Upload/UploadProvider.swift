import Foundation

/// Typed wrapper around the raw `"uploadProvider"` UserDefaults string.
///
/// Replaces the scattered `"gdrive"` / `"s3"` / `"cfimgbed"` / `"imgbb"` string
/// literals that previously appeared in both `RecordingFlowCoordinator` and
/// `ScreenshotOutputCoordinator`. Routing decisions now read `UploadProvider.current`
/// and branch on the enum, so a typo can no longer silently select the wrong provider.
@MainActor
enum UploadProvider: String {
    case imgbb
    case gdrive
    case s3
    case cfimgbed

    /// Current provider from UserDefaults, falling back to `.imgbb` (matching the
    /// historical default) when unset or unrecognized.
    static var current: UploadProvider {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.uploadProvider) ?? "imgbb"
        return UploadProvider(rawValue: raw) ?? .imgbb
    }

    /// Localized error text if this provider is not ready to upload (missing config /
    /// not signed in). `nil` means ready. imgbb has no preflight check here because
    /// `ImageUploader` validates its API key at upload time.
    var readinessErrorText: String? {
        switch self {
        case .gdrive:
            if !GoogleDriveUploader.shared.isSignedIn {
                return L("Sign in to Google Drive in Settings")
            }
            return nil
        case .s3:
            if !S3Uploader.shared.isConfigured {
                return L("Configure S3 in Settings")
            }
            return nil
        case .cfimgbed:
            if !CloudflareImgBedUploader.shared.isConfigured {
                return L("Configure CloudFlare ImgBed in Settings")
            }
            return nil
        case .imgbb:
            return nil
        }
    }

    /// Whether this provider can upload video. imgbb is image-only.
    var supportsVideo: Bool {
        self != .imgbb
    }
}
