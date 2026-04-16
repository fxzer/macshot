import SwiftUI

/// Single grid cell for upload history item
struct UploadHistoryCell: View {
    let item: UploadHistoryItem
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var showCopyCheckmark = false
    @State private var showDeleteCheckmark = false

    var body: some View {
        let cornerRadius: CGFloat = 8

        ZStack {
            // 1. 缩略图 - 尝试从历史缓存加载
            let thumbnailImage = loadThumbnailImage()
            Group {
                if let nsImage = thumbnailImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture {
                // 点击打开浏览器
                openLink()
            }

            VStack {
                Spacer()
                Text(item.providerName)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(.bottom, 6)
            }

            if isHovering || showCopyCheckmark || showDeleteCheckmark {
                VStack(spacing: 4) {
                    Button(action: {
                        copyLink()
                    }) {
                        overlayButtonIcon(
                            systemName: showCopyCheckmark ? "checkmark.circle.fill" : "doc.on.doc",
                            foregroundColor: showCopyCheckmark ? .green : .white
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))

                    if !item.deleteURL.isEmpty {
                        Button(action: {
                            copyDeleteURL()
                        }) {
                            overlayButtonIcon(
                                systemName: showDeleteCheckmark ? "checkmark.circle.fill" : "link.badge.minus",
                                foregroundColor: showDeleteCheckmark ? .green : .pink
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func overlayButtonIcon(systemName: String, foregroundColor: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(foregroundColor)
            .frame(width: 28, height: 28)
            .background(.black.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.link, forType: .string)

        // 显示反馈
        withAnimation(.easeOut(duration: 0.2)) {
            showCopyCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showCopyCheckmark = false
            }
        }
    }

    private func copyDeleteURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.deleteURL, forType: .string)

        // 显示反馈
        withAnimation(.easeOut(duration: 0.2)) {
            showDeleteCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showDeleteCheckmark = false
            }
        }
    }

    private func loadThumbnailImage() -> NSImage? {
        // 使用 UploadHistoryStore 的方法获取缩略图 URL
        guard let thumbnailURL = UploadHistoryStore.getThumbnailURL(id: item.id) else {
            return nil
        }

        return NSImage(contentsOf: thumbnailURL)
    }

    private func openLink() {
        guard let url = URL(string: item.link) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Upload history item model
struct UploadHistoryItem: Identifiable {
    let id: String
    let provider: String
    let link: String
    let deleteURL: String
    let timestamp: Date

    var providerIcon: String {
        switch provider {
        case "imgbb": return "cloud.fill"
        case "gdrive": return "icloud.and.arrow.up"
        case "s3": return "square.and.arrow.up.fill"
        default: return "link"
        }
    }

    var providerColor: Color {
        switch provider {
        case "imgbb": return .orange
        case "gdrive": return .blue
        case "s3": return .red
        default: return .gray
        }
    }

    var providerName: String {
        switch provider {
        case "imgbb": return "ImgBB"
        case "gdrive": return "Google Drive"
        case "s3": return "S3"
        default: return provider
        }
    }
}
