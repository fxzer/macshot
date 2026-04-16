import SwiftUI

/// Single grid cell for upload history item
struct UploadHistoryCell: View {
    let item: UploadHistoryItem
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var showCopyFeedback = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. 缩略图（使用占位图，后续可以加载真实缩略图）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                )
                .onTapGesture {
                    // 点击预览（暂未实现）
                }

            // 2. 左上角：服务商图标
            Image(systemName: item.providerIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(5)
                .background(item.providerColor.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(6)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)

            // 3. 底部：服务商名称
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

            // 4. 右上角：复制按钮（悬停时显示）
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
                .padding(.top, 6)
                .padding(.trailing, 6)
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
