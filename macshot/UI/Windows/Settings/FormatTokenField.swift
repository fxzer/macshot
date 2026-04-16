import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 外部紧凑入口：左侧标题，右侧路径摘要和设置按钮。
struct SaveLocationSettingsRow: View {
    let screenshotPath: String
    let recordingPath: String
    let onBrowseScreenshot: () -> Void
    let onBrowseRecording: () -> Void
    let onClearRecording: () -> Void

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Save folder"))
            Spacer()
            Text(compactSummaryText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(L("Settings…")) {
                showPopover.toggle()
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                SaveLocationPopoverView(
                    screenshotPath: screenshotPath,
                    recordingPath: recordingPath,
                    onBrowseScreenshot: onBrowseScreenshot,
                    onBrowseRecording: onBrowseRecording,
                    onClearRecording: onClearRecording
                )
                .frame(width: 460)
                .padding(16)
            }
        }
    }

    private var compactSummaryText: String {
        let screenshotName = displayName(for: screenshotPath)
        let recordingName = recordingPath == L("Same as screenshots")
            ? recordingPath
            : displayName(for: recordingPath)
        return "\(L("Screenshot")): \(screenshotName)  |  \(L("Recording")): \(recordingName)"
    }

    private func displayName(for path: String) -> String {
        if path == L("Same as screenshots") {
            return path
        }

        let expanded = (path as NSString).expandingTildeInPath
        let lastComponent = URL(fileURLWithPath: expanded).lastPathComponent
        return lastComponent.isEmpty ? path : lastComponent
    }
}

/// 外部紧凑入口：左侧标题，右侧预览和设置按钮。
struct FilenameFormatSettingsRow: View {
    @Binding var format: TokenFilenameFormat
    @Binding var previewKind: FilenameOutputKind
    let screenshotExtension: String

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Filename"))
            Spacer()
            Text(compactPreviewText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(L("Settings…")) {
                showPopover.toggle()
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                FormatTokenField(
                    format: $format,
                    previewKind: $previewKind,
                    screenshotExtension: screenshotExtension
                )
                .frame(width: 430)
                .padding(16)
            }
        }
    }

    /// 外层一行只展示文件名规则生成后的主体名称。
    private var compactPreviewText: String {
        FilenameTemplateEngine.makeBaseName(
            format: format,
            kind: previewKind
        )
    }
}

/// Popover 里的完整编辑器：
/// - 顶部是块编辑区
/// - 中间是预览类型切换和实时预览
/// - 底部是变量池
struct FormatTokenField: View {
    @Binding var format: TokenFilenameFormat
    @Binding var previewKind: FilenameOutputKind
    let screenshotExtension: String

    @State private var blocks: [FilenameFormatBlock] = []
    @State private var lastSyncedSerialized = ""
    @State private var highlightedDropIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Filename"))
                .font(.headline)

            blockEditor

            VStack(alignment: .leading, spacing: 8) {
                Picker(L("Preview"), selection: $previewKind) {
                    ForEach(previewKinds, id: \.self) { kind in
                        Text(kind.localizedLabel).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Text(format.preview(kind: previewKind, fileExtension: fileExtension(for: previewKind)))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tokens")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                HStack(spacing: 8) {
                    symbolPaletteButton(name: "短横线", symbol: "-", isInserted: false)
                    symbolPaletteButton(name: "下划线", symbol: "_", isInserted: false)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(FormatToken.allVariables, id: \.self) { token in
                        VariablePaletteTokenView(
                            token: token,
                            isInserted: containsVariableToken(token),
                            onInsert: {
                                insertVariableTokenAtEnd(token)
                            },
                            onRemove: {
                                removeVariableToken(token)
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            syncBlocksFromFormat(force: true)
        }
        .onChange(of: format.serializedString) { _ in
            syncBlocksFromFormat(force: false)
        }
    }

    private var previewKinds: [FilenameOutputKind] {
        [.screenshot, .recording]
    }

    private func fileExtension(for kind: FilenameOutputKind) -> String {
        switch kind {
        case .screenshot:
            return screenshotExtension
        case .recording:
            return "mp4"
        case .gif:
            return "gif"
        }
    }

    private var blockEditor: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    dropSlot(at: index)
                    blockView(for: block)
                }
                dropSlot(at: blocks.count)
            }
            .padding(8)
        }
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func blockView(for block: FilenameFormatBlock) -> some View {
        FilenameFormatBlockView(
            block: block,
            onDelete: {
                removeBlock(id: block.id)
            }
        )
    }

    private func dropSlot(at index: Int) -> some View {
        FilenameFormatDropSlot(isHighlighted: highlightedDropIndex == index)
            .dropDestination(for: FilenameFormatDragPayload.self) { items, _ in
                handleDrop(items, at: index)
            } isTargeted: { isTargeted in
                if isTargeted {
                    highlightedDropIndex = index
                } else if highlightedDropIndex == index {
                    highlightedDropIndex = nil
                }
            }
    }

    private func handleDrop(_ items: [FilenameFormatDragPayload], at index: Int) -> Bool {
        guard let payload = items.first else { return false }
        highlightedDropIndex = nil
        guard canInsert(payload: payload) else { return false }
        applyDrop(payload, at: index)
        return true
    }

    private func insertTextSymbolAtEnd(_ symbol: String) {
        blocks.append(.text(symbol))
        syncFormatFromBlocks()
    }

    private func insertVariableTokenAtEnd(_ token: FormatToken) {
        guard !containsVariableToken(token) else { return }
        blocks.append(.variable(token))
        syncFormatFromBlocks()
    }

    private func removeVariableToken(_ token: FormatToken) {
        blocks.removeAll { $0.variableToken == token }
        syncFormatFromBlocks()
    }

    private func removeBlock(id: UUID) {
        blocks.removeAll { $0.id == id }
        if blocks.isEmpty {
            blocks = []
        }
        syncFormatFromBlocks()
    }

    private func applyDrop(_ payload: FilenameFormatDragPayload, at index: Int) {
        switch payload.source {
        case .editor:
            guard let blockID = payload.blockID,
                  let sourceIndex = blocks.firstIndex(where: { $0.id == blockID }) else { return }

            let block = blocks.remove(at: sourceIndex)
            let destinationIndex = sourceIndex < index ? index - 1 : index
            blocks.insert(block, at: max(0, min(destinationIndex, blocks.count)))

        case .palette:
            guard let block = payload.makeBlock() else { return }
            blocks.insert(block, at: max(0, min(index, blocks.count)))
        }

        syncFormatFromBlocks()
    }

    private func syncBlocksFromFormat(force: Bool) {
        let serialized = format.serializedString
        guard force || serialized != lastSyncedSerialized else { return }

        lastSyncedSerialized = serialized
        let mappedBlocks = FilenameFormatBlock.blocks(from: format)
        blocks = mappedBlocks
    }

    private func syncFormatFromBlocks() {
        let tokens = blocks.compactMap(\.formatToken)
        let newFormat = TokenFilenameFormat(tokens: tokens)
        lastSyncedSerialized = newFormat.serializedString
        if format != newFormat {
            format = newFormat
        }
    }

    private func symbolPaletteButton(name: String, symbol: String, isInserted: Bool) -> some View {
        SymbolPaletteTokenView(name: name, symbol: symbol, isInserted: isInserted) {
            insertTextSymbolAtEnd(symbol)
        }
    }

    private func containsVariableToken(_ token: FormatToken) -> Bool {
        blocks.contains { $0.variableToken == token }
    }

    private func containsTextSymbol(_ symbol: String) -> Bool {
        blocks.contains { $0.kind == .text && $0.text == symbol }
    }

    private func canInsert(payload: FilenameFormatDragPayload) -> Bool {
        if let tokenCode = payload.tokenCode,
           let token = FormatToken.fromVariableCode(tokenCode) {
            return !containsVariableToken(token)
        }

        if payload.textValue != nil {
            return true
        }

        return true
    }
}

private struct SaveLocationPopoverView: View {
    let screenshotPath: String
    let recordingPath: String
    let onBrowseScreenshot: () -> Void
    let onBrowseRecording: () -> Void
    let onClearRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Save folder"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                locationRow(
                    title: L("Screenshot"),
                    path: screenshotPath,
                    actionTitle: L("Browse…"),
                    action: onBrowseScreenshot
                )

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    locationRow(
                        title: L("Recording"),
                        path: recordingPath,
                        actionTitle: L("Browse…"),
                        action: onBrowseRecording
                    )

                    HStack {
                        Text(L("GIF uses the recording folder."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(L("Clear")) {
                            onClearRecording()
                        }
                        .disabled(recordingPath == L("Same as screenshots"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func locationRow(title: String, path: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(alignment: .center, spacing: 10) {
                Text(path)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)

                Button(actionTitle, action: action)
            }
        }
    }
}

private struct FilenameFormatBlock: Identifiable, Hashable {
    enum Kind: String, Codable {
        case text
        case variable
    }

    let id: UUID
    var kind: Kind
    var text: String
    var variableToken: FormatToken?

    init(id: UUID = UUID(), kind: Kind, text: String, variableToken: FormatToken?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.variableToken = variableToken
    }

    static func text(_ value: String, id: UUID = UUID()) -> FilenameFormatBlock {
        FilenameFormatBlock(id: id, kind: .text, text: value, variableToken: nil)
    }

    static func variable(_ token: FormatToken, id: UUID = UUID()) -> FilenameFormatBlock {
        FilenameFormatBlock(id: id, kind: .variable, text: "", variableToken: token)
    }

    init(token: FormatToken) {
        switch token {
        case .text(let value):
            self = .text(value)
        default:
            self = .variable(token)
        }
    }

    var formatToken: FormatToken? {
        switch kind {
        case .text:
            return .text(text)
        case .variable:
            return variableToken
        }
    }

    var editorPayload: FilenameFormatDragPayload {
        .editor(blockID: id)
    }

    static func blocks(from format: TokenFilenameFormat) -> [FilenameFormatBlock] {
        format.tokens.map(FilenameFormatBlock.init(token:))
    }
}

private struct FilenameFormatDragPayload: Codable, Hashable, Transferable {
    enum Source: String, Codable {
        case editor
        case palette
    }

    let source: Source
    let blockID: UUID?
    let tokenCode: String?
    let textValue: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .filenameFormatBlockPayload)
    }

    static func editor(blockID: UUID) -> FilenameFormatDragPayload {
        FilenameFormatDragPayload(source: .editor, blockID: blockID, tokenCode: nil, textValue: nil)
    }

    static func palette(token: FormatToken) -> FilenameFormatDragPayload {
        FilenameFormatDragPayload(source: .palette, blockID: nil, tokenCode: token.variableCode, textValue: nil)
    }

    static func palette(text: String) -> FilenameFormatDragPayload {
        FilenameFormatDragPayload(source: .palette, blockID: nil, tokenCode: nil, textValue: text)
    }

    func makeBlock() -> FilenameFormatBlock? {
        if let tokenCode, let token = FormatToken.fromVariableCode(tokenCode) {
            return .variable(token)
        }
        if let textValue {
            return .text(textValue)
        }
        return nil
    }
}

private struct FilenameFormatDropSlot: View {
    let isHighlighted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
            .frame(width: isHighlighted ? 8 : 4, height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isHighlighted ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.2),
                        lineWidth: isHighlighted ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.12), value: isHighlighted)
    }
}

private struct FilenameFormatBlockView: View {
    let block: FilenameFormatBlock
    let onDelete: () -> Void

    var body: some View {
        Text(displayText)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.primary)
            .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onDelete)
    }

    private var backgroundColor: Color {
        block.kind == .variable
            ? Color.accentColor.opacity(0.10)
            : Color(nsColor: .windowBackgroundColor)
    }

    private var borderColor: Color {
        block.kind == .variable
            ? Color.accentColor.opacity(0.45)
            : Color(nsColor: .separatorColor)
    }

    private var displayText: String {
        block.kind == .text ? block.text : (block.variableToken?.variableCode ?? "")
    }
}

private struct VariablePaletteTokenView: View {
    let token: FormatToken
    let isInserted: Bool
    let onInsert: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        let content = HStack(spacing: 6) {
            Text(token.label)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Text(token.variableCode ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(isInserted ? 0.92 : 1)
        .onTapGesture {
            if isInserted {
                onRemove()
            } else {
                onInsert()
            }
        }
        .onHover { isHovered = $0 }

        if isInserted {
            content.allowsHitTesting(true)
        } else {
            content
                .draggable(FilenameFormatDragPayload.palette(token: token)) {
                    Text(token.variableCode ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
                .allowsHitTesting(true)
        }
    }

    private var backgroundColor: Color {
        if isInserted {
            return Color.accentColor.opacity(0.18)
        }
        return isHovered ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        isInserted ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor)
    }
}

private struct SymbolPaletteTokenView: View {
    let name: String
    let symbol: String
    let isInserted: Bool
    let onInsert: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Text(symbol)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(isInserted ? 0.92 : 1)
        .onTapGesture {
            guard !isInserted else { return }
            onInsert()
        }
        .onHover { isHovered = $0 }
        .draggable(FilenameFormatDragPayload.palette(text: symbol)) {
            Text(symbol)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
        }
    }

    private var backgroundColor: Color {
        if isInserted {
            return Color.accentColor.opacity(0.18)
        }
        return isHovered ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        isInserted ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor)
    }
}

private extension UTType {
    static let filenameFormatBlockPayload = UTType(exportedAs: "com.fxzer.macshot.filename-format-block-payload")
}
