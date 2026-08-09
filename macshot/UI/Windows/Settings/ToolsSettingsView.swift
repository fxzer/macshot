import SwiftUI

/// 工具设置视图 - 使用 Form 容器，四列复选框布局
struct ToolsSettingsView: View {

    @State private var enabledTools: Set<Int>
    @State private var enabledActions: Set<Int>

    // 画笔 Drawing - 按工具栏顺序：Pencil, Line, Arrow, Marker
    private let drawingTools: [(tag: Int, label: String)] = [
        (AnnotationTool.pencil.rawValue, L("Pencil")),
        (AnnotationTool.line.rawValue, L("Line")),
        (AnnotationTool.arrow.rawValue, L("Arrow")),
        (AnnotationTool.marker.rawValue, L("Marker")),
    ]

    // 形状 Shapes - 按工具栏顺序：Rectangle, Ellipse, Pixelate, Loupe
    private let shapeTools: [(tag: Int, label: String)] = [
        (AnnotationTool.rectangle.rawValue, L("Rectangle")),
        (AnnotationTool.ellipse.rawValue, L("Ellipse")),
        (AnnotationTool.pixelate.rawValue, L("Censor")),
        (AnnotationTool.loupe.rawValue, L("Loupe")),
    ]

    // 标注 Annotation - 按工具栏顺序：Text, Number, Stamp, Measure
    private let annotationTools: [(tag: Int, label: String)] = [
        (AnnotationTool.text.rawValue, L("Text")),
        (AnnotationTool.number.rawValue, L("Number")),
        (AnnotationTool.stamp.rawValue, L("Stamp / Emoji")),
        (AnnotationTool.measure.rawValue, L("Measure")),
    ]

    // 颜色 Color
    private let colorTools: [(tag: Int, label: String)] = [
        (AnnotationTool.colorSampler.rawValue, L("Color Picker")),
    ]

    // 效果 Effects
    private let effectActions: [(tag: Int, label: String)] = [
        (1011, L("Invert Colors")),
        (1013, L("Adjust")),
        (1004, L("Beautify")),
        (1005, L("Remove Background")),
        (1006, L("Auto-Redact")),
    ]

    // 快捷操作 Quick Actions - 对应底部工具栏的取色/固定/保存/复制
    private let quickActions: [(tag: Int, label: String)] = [
        (1016, L("Color Picker")),  // 1016 = Color Picker action tag
        (1002, L("Pin")),
        (1014, L("Save")),
        (1015, L("Copy")),
    ]

    // 会话操作 Session Actions - 对应右侧工具栏的关闭/在编辑器打开/上传/分享
    private let sessionActions: [(tag: Int, label: String)] = [
        (1017, L("Cancel")),  // 1017 = Cancel action tag
        (1018, L("Open in Editor")),  // 1018 = Detach action tag
        (1001, L("Upload")),
        (1012, L("Share")),
    ]

    // 捕获操作 Capture Actions
    private let otherActions: [(tag: Int, label: String)] = [
        (1003, L("OCR")),
        (1008, L("Translate")),
        (1010, L("Scroll Capture")),
    ]

    init() {
        let allToolDefaults: [Int] = [
            AnnotationTool.pencil.rawValue, AnnotationTool.line.rawValue,
            AnnotationTool.arrow.rawValue, AnnotationTool.rectangle.rawValue,
            AnnotationTool.ellipse.rawValue, AnnotationTool.marker.rawValue,
            AnnotationTool.text.rawValue, AnnotationTool.number.rawValue,
            AnnotationTool.pixelate.rawValue, AnnotationTool.loupe.rawValue,
            AnnotationTool.stamp.rawValue, AnnotationTool.measure.rawValue,
        ]
        let allActionDefaults: [Int] = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018]

        let tools = UserDefaults.standard.array(forKey: "enabledTools") as? [Int] ?? allToolDefaults
        let actions = UserDefaults.standard.array(forKey: "enabledActions") as? [Int] ?? allActionDefaults
        _enabledTools = State(initialValue: Set(tools))
        _enabledActions = State(initialValue: Set(actions))
    }

    var body: some View {
        Form {
            // MARK: - 绘制工具
            Section {
                ToolGrid(items: drawingTools, enabled: $enabledTools, key: "enabledTools")
            } header: {
                Text(L("Drawing"))
            }

            // MARK: - 形状工具
            Section {
                ToolGrid(items: shapeTools, enabled: $enabledTools, key: "enabledTools")
            } header: {
                Text(L("Shapes"))
            }

            // MARK: - 标注工具
            Section {
                ToolGrid(items: annotationTools, enabled: $enabledTools, key: "enabledTools")
            } header: {
                Text(L("Annotation"))
            }

            // MARK: - 快捷操作
            Section {
                ToolGrid(items: quickActions, enabled: $enabledActions, key: "enabledActions")
            } header: {
                Text(L("Quick Actions"))
            }

            // MARK: - 会话操作
            Section {
                ToolGrid(items: sessionActions, enabled: $enabledActions, key: "enabledActions")
            } header: {
                Text(L("Session Actions"))
            }

            // MARK: - 效果
            Section {
                ToolGrid(items: effectActions, enabled: $enabledActions, key: "enabledActions")
            } header: {
                Text(L("Effects"))
            }

            // MARK: - 捕获操作
            Section {
                ToolGrid(items: otherActions, enabled: $enabledActions, key: "enabledActions")
            } header: {
                Text(L("Capture Actions"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 四列网格布局

struct ToolGrid: View {
    let items: [(tag: Int, label: String)]
    @Binding var enabled: Set<Int>
    let key: String

    private let columns = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<columns, id: \.self) { col in
                        let idx = row * columns + col
                        if idx < items.count {
                            let item = items[idx]
                            Toggle(item.label, isOn: toggleBinding(item: item))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var rows: Int {
        Int(ceil(Double(items.count) / Double(columns)))
    }

    private func toggleBinding(item: (tag: Int, label: String)) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(item.tag) },
            set: { newValue in
                if newValue {
                    enabled.insert(item.tag)
                } else {
                    enabled.remove(item.tag)
                }
                UserDefaults.standard.set(Array(enabled), forKey: key)
            }
        )
    }
}

#Preview {
    ToolsSettingsView()
        .frame(width: 560, height: 600)
}