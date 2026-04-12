import SwiftUI

struct ToolsSettingsView: View {

    @State private var enabledTools: Set<Int>
    @State private var enabledActions: Set<Int>

    private let annotationTools: [(tag: Int, label: String)] = [
        (AnnotationTool.pencil.rawValue, L("Pencil")),
        (AnnotationTool.line.rawValue, L("Line")),
        (AnnotationTool.arrow.rawValue, L("Arrow")),
        (AnnotationTool.rectangle.rawValue, L("Rectangle")),
        (AnnotationTool.ellipse.rawValue, L("Ellipse")),
        (AnnotationTool.marker.rawValue, L("Marker")),
        (AnnotationTool.text.rawValue, L("Text")),
        (AnnotationTool.number.rawValue, L("Number / Counter")),
        (AnnotationTool.pixelate.rawValue, L("Censor")),
        (AnnotationTool.loupe.rawValue, L("Magnify (Loupe)")),
        (AnnotationTool.stamp.rawValue, L("Stamp / Emoji")),
        (AnnotationTool.colorSampler.rawValue, L("Color Picker")),
        (AnnotationTool.measure.rawValue, L("Measure")),
    ]

    private let bottomActionItems: [(tag: Int, label: String)] = [
        (1011, L("Invert Colors")),
        (1013, L("Adjust (Image Effects)")),
        (1004, L("Beautify")),
        (1005, L("Remove Background")),
    ]

    private let rightActionItems: [(tag: Int, label: String)] = [
        (1001, L("Upload")),
        (1002, L("Pin (floating window)")),
        (1003, L("OCR (extract text)")),
        (1006, L("Auto-Redact sensitive data")),
        (1008, L("Translate")),
        (1009, L("Record screen")),
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
            // MARK: - Annotation Tools
            Section {
                ForEach(annotationTools, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledTools, key: "enabledTools")
                }
            } header: {
                Text(L("Annotation Tools"))
            } footer: {
                Text(L("Hidden tools are removed from the bottom toolbar."))
            }

            // MARK: - Bottom Toolbar Actions
            Section {
                ForEach(bottomActionItems, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledActions, key: "enabledActions")
                }
            } header: {
                Text(L("Bottom Toolbar Actions"))
            } footer: {
                Text(L("Hidden actions are removed from the bottom toolbar."))
            }

            // MARK: - Right Toolbar Actions
            Section {
                ForEach(rightActionItems, id: \.tag) { item in
                    toggleRow(item: item, enabled: $enabledActions, key: "enabledActions")
                }
            } header: {
                Text(L("Right Toolbar Actions"))
            } footer: {
                Text(L("Hidden actions are removed from the right toolbar."))
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
