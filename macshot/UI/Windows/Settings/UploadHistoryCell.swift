import SwiftUI

/// Single grid cell for upload history item
struct UploadHistoryCell: View {
    let item: UploadHistoryItem
    @State private var isHovering = false
    @State private var showCopyCheckmark = false

    var body: some View {
        let cornerRadius: CGFloat = 8

        // 缩略图
        let thumbnailImage = loadThumbnailImage()
        let baseView: some View = Group {
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

        // 完整的卡片视图，使用 overlay 来定位复制按钮
        return baseView
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(Rectangle()) // 确保整个区域可点击
            .onTapGesture {
                openLink()
            }
            .overlay(alignment: .topTrailing) {
                // 复制按钮 - 使用 overlay + topTrailing 确保始终相对于卡片右上角定位
                Group {
                    if isHovering || showCopyCheckmark {
                        Button(action: {
                            copyLink()
                        }) {
                            overlayButtonIcon(
                                systemName: showCopyCheckmark ? "checkmark.circle.fill" : "doc.on.doc",
                                foregroundColor: showCopyCheckmark ? .green : .white
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(8) // 距离边缘8px
                    }
                }
                .frame(width: 80, height: 80, alignment: .topTrailing)
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .animation(.easeOut(duration: 0.2), value: showCopyCheckmark)
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

    private func loadThumbnailImage() -> NSImage? {
        // 使用 UploadHistoryStore 的方法获取缩略图 URL
        guard let thumbnailURL = UploadHistoryStore.getThumbnailURL(id: item.id) else {
            return nil
        }

        return NSImage(contentsOf: thumbnailURL)
    }

    private func openLink() {
        // imgbb 用 deleteURL（如果有的话），其他用 link
        let urlString = (item.provider == "imgbb" && !item.deleteURL.isEmpty) ? item.deleteURL : item.link
        guard let url = URL(string: urlString) else { return }
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
