import SwiftUI

/// A compact button that shows the current filename format and opens a popover for editing
struct FilenameFormatSettingsButton: View {
    @Binding var format: FilenameFormat
    let fileExtension: String
    let title: String

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
            Spacer()
            Text(currentFormatDisplay)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(L("Format…")) {
                showPopover.toggle()
            }
            .popover(isPresented: $showPopover) {
                FilenameFormatPopoverContent(
                    format: $format,
                    fileExtension: fileExtension
                )
                .frame(width: 320, height: 380)
                .padding()
            }
        }
    }

    private var currentFormatDisplay: String {
        let components = format.formatTimestamp()
        return "macshot-\(components).\(fileExtension)"
    }
}

/// The popover content for editing filename format
struct FilenameFormatPopoverContent: View {
    @Binding var format: FilenameFormat
    let fileExtension: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(L("Filename Format"))
                .font(.headline)

            Text(L("Select components to include in the filename:"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Checkboxes in two columns
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    CheckboxRow(
                        title: L("Year"),
                        subtitle: "YYYY",
                        isEnabled: $format.includeYear
                    )
                    CheckboxRow(
                        title: L("Month"),
                        subtitle: "MM",
                        isEnabled: $format.includeMonth
                    )
                    CheckboxRow(
                        title: L("Day"),
                        subtitle: "DD",
                        isEnabled: $format.includeDay
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    CheckboxRow(
                        title: L("Hour"),
                        subtitle: "HH",
                        isEnabled: $format.includeHour
                    )
                    CheckboxRow(
                        title: L("Minute"),
                        subtitle: "MM",
                        isEnabled: $format.includeMinute
                    )
                    CheckboxRow(
                        title: L("Second"),
                        subtitle: "SS",
                        isEnabled: $format.includeSecond
                    )
                }
            }

            Divider()

            // Preview
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Preview"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundColor(.secondary)
                    Text(previewText)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }

            Spacer()
        }
    }

    private var previewText: String {
        let timestamp = format.formatTimestamp()
        return "macshot-\(timestamp).\(fileExtension)"
    }
}

/// A single checkbox row with title and subtitle
struct CheckboxRow: View {
    let title: String
    let subtitle: String
    @Binding var isEnabled: Bool

    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    FilenameFormatSettingsButton(
        format: .constant(FilenameFormat.default),
        fileExtension: "png",
        title: L("Filename format")
    )
    .padding()
    .frame(width: 500)
}
