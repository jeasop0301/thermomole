import SwiftUI
import ThermoMoleCore

struct OperationStatePill: View {
    var state: OperationState

    var body: some View {
        HStack(spacing: 6) {
            if state.phase == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
            }
            Text(state.message)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.16)))
        .foregroundStyle(tint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Operation status"))
        .accessibilityValue(Text(state.message))
    }

    private var tint: Color {
        switch state.phase {
        case .idle: .secondary
        case .running: Color.oceanAccent
        case .finished: Color.leafAccent
        case .failed: .red
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProgressPanel: View {
    var title: String
    var message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softPanel()
    }
}

struct IconButton: View {
    var systemName: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
