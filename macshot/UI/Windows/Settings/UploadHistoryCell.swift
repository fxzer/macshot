import SwiftUI

/// Single grid cell for upload history item
struct UploadHistoryCell: View {
    let item: UploadHistoryItem
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var showCopyFeedback = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. 缩略图 - 尝试从历史缓存加载
            let thumbnailImage = loadThumbnailImage()
            Group {
                if let nsImage = thumbnailImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    // 占位图
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                // 点击预览（暂未实现）
            }

            // 2. 底部：服务商名称
            VStack {
                Spacer()
                Text(item.providerName)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .cornerRadius(4)
            }

            // 3. 右上角：复制按钮（悬停时显示）
            VStack {
                HStack {
                    Spacer()
                    if isHovering {
                        Button(action: {
                            copyLink()
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))

                        // ImgBB 特殊处理：如果有删除URL，显示第二个按钮
                        if !item.deleteURL.isEmpty {
                            Button(action: {
                                copyDeleteURL()
                            }) {
                                Image(systemName: "link.badge.minus")
                                    .font(.title3)
                                    .foregroundColor(.pink)
                                    .padding(6)
                                    .background(.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                            .padding(.trailing, 4)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.trailing, 4)
                Spacer()
                Spacer()
            }

            // 复制成功反馈
            if showCopyFeedback {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        Text("已复制")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.link, forType: .string)

        // 显示反馈
        withAnimation(.easeOut(duration: 0.2)) {
            showCopyFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyFeedback = false
            }
        }
    }

    private func copyDeleteURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.deleteURL, forType: .string)

        // 显示反馈
        withAnimation(.easeOut(duration: 0.2)) {
            showCopyFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyFeedback = false
            }
        }
    }

    private func loadThumbnailImage() -> NSImage? {
        // 从历史缓存加载缩略图
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let historyDir = appSupportURL.appendingPathComponent("com.fxzer.macshot/history")
        let thumbnailDir = historyDir.appendingPathComponent("thumbnails")

        // 使用 ID 作为文件名
        let thumbnailURL = thumbnailDir.appendingPathComponent("\(item.id).jpg")

        guard fileManager.fileExists(atPath: thumbnailURL.path) else {
            return nil
        }

        return NSImage(contentsOf: thumbnailURL)
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
