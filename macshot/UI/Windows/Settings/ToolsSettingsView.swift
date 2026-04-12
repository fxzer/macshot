import SwiftUI

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
        (AnnotationTool.pixelate.rawValue, L("Pixelate")),
        (AnnotationTool.loupe.rawValue, L("Loupe")),
    ]

    // 标注 Annotation - 按工具栏顺序：Text, Number, Stamp, Measure
    private let annotationTools: [(tag: Int, label: String)] = [
        (AnnotationTool.text.rawValue, L("Text")),
        (AnnotationTool.number.rawValue, L("Number")),
        (AnnotationTool.stamp.rawValue, L("Stamp")),
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
    ]

    // 其他操作 Other Actions
    private let otherActions: [(tag: Int, label: String)] = [
        (1001, L("Upload")),
        (1002, L("Pin")),
        (1003, L("OCR")),
        (1006, L("Auto-Redact")),
        (1008, L("Translate")),
        (1009, L("Record")),
        (1010, L("Scroll Capture")),
        (1012, L("Share")),
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
        let allActionDefaults: [Int] = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010]

        let tools = UserDefaults.standard.array(forKey: "enabledTools") as? [Int] ?? allToolDefaults
        let actions = UserDefaults.standard.array(forKey: "enabledActions") as? [Int] ?? allActionDefaults
        _enabledTools = State(initialValue: Set(tools))
        _enabledActions = State(initialValue: Set(actions))
    }

    var body: some View {
        Form {
            // MARK: - Drawing Tools (画笔)
            Section {
                ForEach(drawingTools, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledTools, key: "enabledTools")
                }
            } header: {
                Text(L("Drawing"))
            }

            // MARK: - Shape Tools (形状)
            Section {
                ForEach(shapeTools, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledTools, key: "enabledTools")
                }
            } header: {
                Text(L("Shapes"))
            }

            // MARK: - Annotation Tools (标注)
            Section {
                ForEach(annotationTools, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledTools, key: "enabledTools")
                }
            } header: {
                Text(L("Annotation"))
            }

            // MARK: - Color Tools (颜色)
            Section {
                ForEach(colorTools, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledTools, key: "enabledTools")
                }
            } header: {
                Text(L("Color"))
            }

            // MARK: - Effect Tools (效果)
            Section {
                ForEach(effectActions, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledActions, key: "enabledActions")
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Effects"))
                    Text(L("Hidden tools are removed from the toolbar."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Other Actions (其他操作)
            Section {
                ForEach(otherActions, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledActions, key: "enabledActions")
                }
            } header: {
                Text(L("Other"))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func toggleRow(item: (tag: Int, label: String), enabled: Binding<Set<Int>>, key: String) -> some View {
        Toggle(item.label, isOn: Binding(
            get: { enabled.wrappedValue.contains(item.tag) },
            set: { newValue in
                if newValue {
                    enabled.wrappedValue.insert(item.tag)
                } else {
                    enabled.wrappedValue.remove(item.tag)
                }
                UserDefaults.standard.set(Array(enabled.wrappedValue), forKey: key)
            }
        ))
    }
}
