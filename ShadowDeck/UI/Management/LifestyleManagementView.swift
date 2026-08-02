//
//  LifestyleManagementView.swift
//  ShadowDeck
//
//  Lifestyle CRUD, monthly burn, process month (1–3), prepay, reserve, ledger.
//

import SwiftUI

struct LifestyleManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void
    var onStatus: ((String) -> Void)?

    @State private var expandedID: UUID?
    @State private var showAdd = false
    @State private var confirmProcess = false
    @State private var processMonths = 1
    @State private var showReserveSheet = false
    @State private var reserveAmount = 0
    @State private var reserveIsDeposit = true
    @State private var prepayLifestyleID: UUID?
    @State private var prepayMonths = 1
    @State private var errorMessage: String?

    private var burn: LifestyleBurnSummary {
        LifestyleTracker.burnSummary(for: character)
    }

    var body: some View {
        ManagementListChrome(
            title: "Lifestyle",
            subtitle: "Monthly costs, prepaid months, and a reserve buffer used first when you process rent.",
            onAdd: { showAdd = true },
            addLabel: "Add Lifestyle",
            onLookUp: {
                RulesReferenceOpener.request(query: "lifestyle", character: character)
            },
            lookUpLabel: "Look up"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                summaryHeader

                if character.lifestyles.isEmpty {
                    ManagementEmptyState(
                        title: "No Lifestyles",
                        systemImage: "house",
                        message: "Add a safehouse or loft, or re-import from Chummer. Look up covers levels, Process Month, and reserve."
                    )
                } else {
                    List {
                        ForEach(character.lifestyles) { life in
                            lifestyleBlock(life)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 200)
                }

                ledgerSection
            }
        }
        .sheet(isPresented: $showAdd) {
            addSheet
        }
        .sheet(isPresented: Binding(
            get: { prepayLifestyleID != nil },
            set: { if !$0 { prepayLifestyleID = nil } }
        )) {
            if let id = prepayLifestyleID {
                prepaySheet(for: id)
            }
        }
        .sheet(isPresented: $showReserveSheet) {
            reserveSheet
        }
        .confirmationDialog(
            processMonths == 1 ? "Process 1 month of lifestyle costs?" : "Process \(processMonths) months of lifestyle costs?",
            isPresented: $confirmProcess,
            titleVisibility: .visible
        ) {
            Button("Process \(processMonths) Month\(processMonths == 1 ? "" : "s")") {
                applyProcessMonths()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let needed = LifestyleTracker.cashRequiredToProcess(character: character, months: processMonths)
            Text(
                needed == 0
                    ? "All active lifestyles are covered by prepaid months for this period."
                    : "Cash due: ¥\(needed.formatted()). Reserve is used first, then nuyen. Shortfall blocks the whole action."
            )
        }
    }

    // MARK: - Header

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                statusChip(burn.overallStatus)
                Spacer()
                if let last = character.lifestyleLastProcessedAt {
                    Text("Last processed \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never processed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                metric("Monthly Burn", "¥\(burn.monthlyBurn.formatted())")
                metric("Cash Due (1 mo)", "¥\(burn.cashDue.formatted())")
                metric("Nuyen", "¥\(character.nuyen.formatted())")
                metric("Reserve", "¥\(character.lifestyleNuyenReserve.formatted())")
                metric("Liquidity", "¥\(burn.liquidity.formatted())")
                if burn.activeCount > 0 {
                    metric("Min Prepaid", "\(burn.minimumPrepaidMonths) mo")
                }
            }

            Text("Lifestyle reserve is a buffer used first when paying monthly costs, before regular nuyen.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Picker("Months", selection: $processMonths) {
                    Text("1 mo").tag(1)
                    Text("2 mo").tag(2)
                    Text("3 mo").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                AppChromeButton.title(
                    "Process Month…",
                    help: "Advance 1–3 months: consume prepaid or charge reserve then nuyen",
                    isEnabled: burn.activeCount > 0
                ) {
                    errorMessage = nil
                    confirmProcess = true
                }

                AppChromeButton.title("Add to Reserve…", help: "Deposit nuyen to lifestyle reserve") {
                    reserveIsDeposit = true
                    reserveAmount = min(1_000, max(0, character.nuyen))
                    showReserveSheet = true
                }
                AppChromeButton.title(
                    "Withdraw Reserve…",
                    help: "Withdraw from lifestyle reserve",
                    isEnabled: character.lifestyleNuyenReserve > 0
                ) {
                    reserveIsDeposit = false
                    reserveAmount = min(1_000, max(0, character.lifestyleNuyenReserve))
                    showReserveSheet = true
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusChip(_ status: LifestyleCoverageStatus) -> some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusBackground(status), in: Capsule())
            .foregroundStyle(statusForeground(status))
    }

    private func statusBackground(_ status: LifestyleCoverageStatus) -> Color {
        switch status {
        case .inactive: Color.secondary.opacity(0.12)
        case .covered: Color.green.opacity(0.18)
        case .due: Color.orange.opacity(0.18)
        case .underfunded: Color.red.opacity(0.16)
        }
    }

    private func statusForeground(_ status: LifestyleCoverageStatus) -> Color {
        switch status {
        case .inactive: .secondary
        case .covered: .green
        case .due: .orange
        case .underfunded: .red
        }
    }

    // MARK: - Rows

    private func lifestyleBlock(_ life: Lifestyle) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedID == life.id },
                set: { expandedID = $0 ? life.id : nil }
            )
        ) {
            editor(life)
                .padding(.vertical, 4)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(life.name.isEmpty ? "Unnamed lifestyle" : life.name)
                        .font(.body.weight(.medium))
                    Text("\(life.level.displayName) · ¥\(life.monthlyCost.formatted())/mo · Prepaid \(life.monthsPrepaid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusChip(
                    LifestyleTracker.status(for: life, liquidity: burn.liquidity)
                )
                Button(role: .destructive) {
                    character.lifestyles.removeAll { $0.id == life.id }
                    onPersist()
                    onStatus?("Removed lifestyle.")
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func editor(_ life: Lifestyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: bindingName(life.id))
                    .textFieldStyle(.roundedBorder)
                Picker("Level", selection: bindingLevel(life.id)) {
                    ForEach(LifestyleLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .frame(maxWidth: 140)
            }
            HStack {
                Text("¥ / month")
                    .foregroundStyle(.secondary)
                TextField("Cost", value: bindingCost(life.id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text("Prepaid mo")
                    .foregroundStyle(.secondary)
                TextField("Months", value: bindingPrepaid(life.id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Toggle("Active", isOn: bindingActive(life.id))
                    .toggleStyle(.checkbox)
                Spacer()
                AppChromeButton.title(
                    "Use SR5 default",
                    help: "Suggested core-book monthly cost for this level (SR5 guidance)"
                ) {
                    updateLifestyle(life.id) {
                        $0.monthlyCost = $0.level.suggestedMonthlyCostSR5
                    }
                }
            }
            TextField("Notes", text: bindingNotes(life.id), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                AppChromeButton.title(
                    "Prepay…",
                    help: "Prepay months of lifestyle",
                    isEnabled: life.isActive
                ) {
                    prepayMonths = 1
                    prepayLifestyleID = life.id
                }
                Spacer()
            }
        }
    }

    // MARK: - Ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Ledger")
                .font(.headline)
            let entries = Array(character.lifestyleLedgerEntries.prefix(20))
            if entries.isEmpty {
                Text("No payments recorded yet. Process a month or prepay to start the log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.kind.displayName)
                                .font(.caption.weight(.semibold))
                            Text(entry.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.amount >= 0 ? "+¥\(entry.amount.formatted())" : "−¥\(abs(entry.amount).formatted())")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(entry.amount >= 0 ? .green : .primary)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Sheets

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Lifestyle")
                .font(.title2.weight(.semibold))
            Text("Defaults use SR5 middle lifestyle guidance; edit freely.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                AppChromeButton.title("Cancel", help: "Close without adding") { showAdd = false }
                Spacer()
                AppChromeButton.title(
                    "Add",
                    help: "Add lifestyle",
                    style: .prominent,
                    keyEquivalent: "\r"
                ) {
                    let level = LifestyleLevel.middle
                    character.lifestyles.append(
                        Lifestyle(
                            name: "Primary",
                            level: level,
                            monthlyCost: level.suggestedMonthlyCostSR5,
                            monthsPrepaid: 1
                        )
                    )
                    onPersist()
                    onStatus?("Added lifestyle.")
                    showAdd = false
                }
            }
        }
        .padding(20)
        .frame(width: 360, height: 160)
    }

    private func prepaySheet(for id: UUID) -> some View {
        let life = character.lifestyles.first { $0.id == id }
        let cost = (life?.monthlyCost ?? 0) * prepayMonths
        return VStack(alignment: .leading, spacing: 12) {
            Text("Prepay \(life?.name ?? "Lifestyle")")
                .font(.title2.weight(.semibold))
            Text("Paid from nuyen only (reserve is kept for Process Month).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("Months: \(prepayMonths)", value: $prepayMonths, in: 1...24)
            Text("Total: ¥\(cost.formatted()) · Available: ¥\(character.nuyen.formatted())")
                .font(.callout.monospacedDigit())
            Spacer()
            HStack {
                AppChromeButton.title("Cancel", help: "Close") { prepayLifestyleID = nil }
                Spacer()
                AppChromeButton.title(
                    "Prepay",
                    help: "Apply prepay from nuyen",
                    style: .prominent,
                    isEnabled: cost > 0 && cost <= character.nuyen,
                    keyEquivalent: "\r"
                ) {
                    do {
                        try LifestyleTracker.prepay(
                            lifestyleID: id,
                            months: prepayMonths,
                            character: &character
                        )
                        onPersist()
                        onStatus?("Prepaid \(prepayMonths) month(s).")
                        errorMessage = nil
                        prepayLifestyleID = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 220)
    }

    private var reserveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reserveIsDeposit ? "Add to Reserve" : "Withdraw Reserve")
                .font(.title2.weight(.semibold))
            Text(
                reserveIsDeposit
                    ? "Move nuyen into the lifestyle reserve (used first on Process Month)."
                    : "Move reserve back into available nuyen."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            TextField("Amount", value: $reserveAmount, format: .number)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                AppChromeButton.title("Cancel", help: "Close") { showReserveSheet = false }
                Spacer()
                AppChromeButton.title(
                    reserveIsDeposit ? "Deposit" : "Withdraw",
                    help: "Confirm reserve change",
                    style: .prominent,
                    keyEquivalent: "\r"
                ) {
                    do {
                        if reserveIsDeposit {
                            try LifestyleTracker.depositToReserve(amount: reserveAmount, character: &character)
                            onStatus?("Deposited ¥\(reserveAmount.formatted()) to reserve.")
                        } else {
                            try LifestyleTracker.withdrawFromReserve(amount: reserveAmount, character: &character)
                            onStatus?("Withdrew ¥\(reserveAmount.formatted()) from reserve.")
                        }
                        onPersist()
                        errorMessage = nil
                        showReserveSheet = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 200)
    }

    // MARK: - Actions

    private func applyProcessMonths() {
        do {
            try LifestyleTracker.processMonths(&character, months: processMonths)
            onPersist()
            onStatus?("Processed \(processMonths) lifestyle month(s).")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            onStatus?(error.localizedDescription)
        }
    }

    // MARK: - Bindings

    private func updateLifestyle(_ id: UUID, _ mutate: (inout Lifestyle) -> Void) {
        guard let i = character.lifestyles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.lifestyles[i])
        onPersist()
    }

    private func bindingName(_ id: UUID) -> Binding<String> {
        Binding(
            get: { character.lifestyles.first { $0.id == id }?.name ?? "" },
            set: { newValue in updateLifestyle(id) { $0.name = newValue } }
        )
    }

    private func bindingLevel(_ id: UUID) -> Binding<LifestyleLevel> {
        Binding(
            get: { character.lifestyles.first { $0.id == id }?.level ?? .low },
            set: { newValue in updateLifestyle(id) { $0.level = newValue } }
        )
    }

    private func bindingCost(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { character.lifestyles.first { $0.id == id }?.monthlyCost ?? 0 },
            set: { newValue in updateLifestyle(id) { $0.monthlyCost = max(0, newValue) } }
        )
    }

    private func bindingPrepaid(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { character.lifestyles.first { $0.id == id }?.monthsPrepaid ?? 0 },
            set: { newValue in updateLifestyle(id) { $0.monthsPrepaid = max(0, newValue) } }
        )
    }

    private func bindingActive(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { character.lifestyles.first { $0.id == id }?.isActive ?? true },
            set: { newValue in updateLifestyle(id) { $0.isActive = newValue } }
        )
    }

    private func bindingNotes(_ id: UUID) -> Binding<String> {
        Binding(
            get: { character.lifestyles.first { $0.id == id }?.notes ?? "" },
            set: { newValue in updateLifestyle(id) { $0.notes = newValue } }
        )
    }
}
