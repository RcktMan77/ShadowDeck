import SwiftUI

// MARK: - Book settings sheet

/// Self-contained editor so library/reader parent updates cannot freeze controls.
struct BookSettingsSheet: View {
    let item: PDFLibraryItem
    let coverURL: URL?
    var onCancel: () -> Void
    var onSave: (_ section: PDFShelfSection, _ bookKey: String?, _ pageOffset: Int) -> Void

    @State private var section: PDFShelfSection
    /// `"none"` | curated key | `"custom"`.
    @State private var keyChoice: String
    @State private var customKey: String
    @State private var pageOffset: Int

    init(
        item: PDFLibraryItem,
        coverURL: URL?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (PDFShelfSection, String?, Int) -> Void
    ) {
        self.item = item
        self.coverURL = coverURL
        self.onCancel = onCancel
        self.onSave = onSave

        _section = State(initialValue: item.shelfSection)
        _pageOffset = State(initialValue: max(0, item.pageOffset))

        if let key = item.bookKey, !key.isEmpty {
            if PDFBookKeyCatalog.curated.contains(where: { $0.key == key }) {
                _keyChoice = State(initialValue: key)
                _customKey = State(initialValue: "")
            } else {
                _keyChoice = State(initialValue: "custom")
                _customKey = State(initialValue: key)
            }
        } else {
            _keyChoice = State(initialValue: "none")
            _customKey = State(initialValue: "")
        }
    }

    private var canSave: Bool {
        if keyChoice == "custom" {
            return !customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var pageOffsetHelp: String {
        if pageOffset == 0 {
            return "Printed p. 1 = PDF page 1 (no offset)."
        }
        let pdfForPrint1 = 1 + pageOffset
        return "Printed p. 1 = PDF page \(pdfForPrint1). Example: chip p. 2 opens PDF page \(2 + pageOffset)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                PDFCoverImage(coverURL: coverURL, cornerRadius: 6)
                    .frame(width: 72, height: 96)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Book settings")
                        .font(.headline)
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text("Shelf section and book key control how this PDF appears and which page chips open it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, 4)

            Form {
                Section {
                    Picker("Shelf section", selection: $section) {
                        ForEach(PDFShelfSection.allCases) { s in
                            Label(s.displayName, systemImage: s.systemImage)
                                .tag(s)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                } header: {
                    Text("Shelf section")
                }

                Section {
                    Picker("Book key", selection: $keyChoice) {
                        Text("None").tag("none")
                        ForEach(PDFBookKeyCatalog.curated, id: \.key) { entry in
                            Text("\(entry.label)  ·  \(entry.key)").tag(entry.key)
                        }
                        Text("Custom…").tag("custom")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    if keyChoice == "custom" {
                        TextField("custom-book-key", text: $customKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }

                    Text("Reference cards open this PDF when their chip uses the same key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Book key (page chips)")
                }

                Section {
                    Stepper(value: $pageOffset, in: 0...50) {
                        HStack {
                            Text("Front matter pages")
                            Spacer()
                            Text("\(pageOffset)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Reference chips use printed page numbers. Unnumbered front matter sits before printed page 1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(pageOffsetHelp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Page numbering")
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 480)
        .onAppear {
            // Belt-and-suspenders: sheet window should own key focus, not PDFKit.
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func save() {
        let resolvedKey: String?
        switch keyChoice {
        case "none":
            resolvedKey = nil
        case "custom":
            let trimmed = customKey.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedKey = trimmed.isEmpty ? nil : trimmed
        default:
            resolvedKey = keyChoice
        }
        onSave(section, resolvedKey, max(0, pageOffset))
    }
}

