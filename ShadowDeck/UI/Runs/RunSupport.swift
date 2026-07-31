//
//  RunSupport.swift
//  ShadowDeck
//
//  Shared chrome for the Run / Mission tracker UI.
//

import SwiftUI

enum RunSupport {
    static let dateStyle: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()

    static func formatDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(dateStyle)
    }

    static func formatNuyen(_ value: Int) -> String {
        "¥\(value.formatted())"
    }
}

struct RunStatusBadge: View {
    let status: RunStatus

    var body: some View {
        Label(status.displayName, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case .planning: Color.secondary.opacity(0.14)
        case .active: Color.orange.opacity(0.18)
        case .completed: Color.green.opacity(0.18)
        case .failed: Color.red.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch status {
        case .planning: .secondary
        case .active: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}

struct RunSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RunTagChips: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Simple wrapping layout for tag chips (macOS-friendly, no extra deps).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
