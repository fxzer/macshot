import SwiftUI

/// Single grid cell for upload history item
struct UploadHistoryCell: View {
    let item: UploadHistoryItem
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var showCopyCheckmark = false
    @State private var showDeleteCheckmark = false

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
                    if isHovering || showCopyCheckmark || showDeleteCheckmark {
                        // 复制主链接按钮
                        Button(action: {
                            copyLink()
                        }) {
                            Image(systemName: showCopyCheckmark ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.title3)
                                .foregroundColor(showCopyCheckmark ? .green : .white)
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
                                Image(systemName: showDeleteCheckmark ? "checkmark.circle.fill" : "link.badge.minus")
                                    .font(.title3)
                                    .foregroundColor(showDeleteCheckmark ? .green : .pink)
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
