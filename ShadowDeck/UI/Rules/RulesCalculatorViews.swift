//
//  RulesCalculatorViews.swift
//  ShadowDeck
//
//  Compact calculator forms for Rules Reference detail pane.
//

import SwiftUI

struct RulesCalculatorHost: View {
    let calculator: CalculatorID
    var edition: Edition
    var houseRules: HouseRules
    var diceRules: DiceHouseRules
    var calcContext: RulesCalcContext = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .foregroundStyle(.tint)
                Text(calculator.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if calcContext != .neutral {
                    Text("From character")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            Group {
                switch calculator {
                case .karmaRaise:
                    KarmaRaiseCalculatorView(
                        edition: edition,
                        houseRules: houseRules,
                        initialFrom: calcContext.sampleSkillRating
                    )
                case .glitchThreshold:
                    GlitchThresholdCalculatorView(
                        edition: edition,
                        diceRules: diceRules,
                        initialPool: max(1, calcContext.sampleSkillRating + calcContext.agility)
                    )
                case .lifestyleBurn:
                    LifestyleBurnCalculatorView(initialMonthly: calcContext.lifestyleMonthlyTotal)
                case .conditionMonitors:
                    ConditionMonitorCalculatorView(
                        initialBody: calcContext.body,
                        initialWillpower: calcContext.willpower
                    )
                case .limitsSR5:
                    LimitsSR5CalculatorView(context: calcContext)
                case .drain:
                    DrainCalculatorView(
                        initialForce: max(1, calcContext.magic),
                        initialWillpower: calcContext.willpower,
                        initialTradition: calcContext.logic
                    )
                case .overwatch:
                    OverwatchCalculatorView()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Shared chrome

private struct CalcResultLine: View {
    let title: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasize ? .body.monospacedDigit().weight(.semibold) : .callout.monospacedDigit())
                .textSelection(.enabled)
        }
    }
}

private struct QuickAidBanner: View {
    var body: some View {
        Text("Quick aid — see your book for the full procedure.")
            .font(.caption2)
            .foregroundStyle(.orange.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Karma

private struct KarmaRaiseCalculatorView: View {
    let edition: Edition
    let houseRules: HouseRules
    var initialFrom: Int = 3

    private enum Mode: String, CaseIterable, Identifiable {
        case skill
        case attribute
        var id: String { rawValue }
        var label: String { self == .skill ? "Skill" : "Attribute" }
    }

    @State private var mode: Mode = .skill
    @State private var category: SkillCategory = .active
    @State private var fromRating: Int
    @State private var toRating: Int

    init(edition: Edition, houseRules: HouseRules, initialFrom: Int = 3) {
        self.edition = edition
        self.houseRules = houseRules
        self.initialFrom = initialFrom
        let from = max(0, min(12, initialFrom))
        _fromRating = State(initialValue: from)
        _toRating = State(initialValue: from + 1)
    }

    private var rules: any EditionRules { RulesRegistry.rules(for: edition) }

    private var total: Int? {
        switch mode {
        case .skill:
            return KarmaRaiseCalculator.cost(
                from: fromRating,
                to: toRating,
                category: category,
                rules: rules,
                houseRules: houseRules
            )
        case .attribute:
            return KarmaRaiseCalculator.attributeCost(
                from: max(1, fromRating),
                to: max(2, toRating),
                rules: rules,
                houseRules: houseRules
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Type", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)

            if mode == .skill {
                Picker("Category", selection: $category) {
                    Text("Active").tag(SkillCategory.active)
                    Text("Knowledge").tag(SkillCategory.knowledge)
                    Text("Language").tag(SkillCategory.language)
                }
                .pickerStyle(.menu)
            }

            HStack {
                Stepper("From \(fromRating)", value: $fromRating, in: mode == .attribute ? 1...11 : 0...12)
                Stepper("To \(toRating)", value: $toRating, in: (fromRating + 1)...(mode == .attribute ? 12 : 13))
            }
            .font(.caption)

            Text("Edition: \(edition.shortName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let total {
                CalcResultLine(title: "Karma cost", value: "\(total)", emphasize: true)
                if toRating == fromRating + 1 {
                    let step = mode == .skill
                        ? KarmaRaiseCalculator.skillStepCost(current: fromRating, category: category, rules: rules)
                        : KarmaRaiseCalculator.attributeStepCost(current: fromRating, rules: rules, houseRules: houseRules)
                    CalcResultLine(title: "Single step", value: "\(step)")
                }
            } else {
                Text("Set To higher than From.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: fromRating) { _, new in
            Task { @MainActor in
                if toRating <= new { toRating = new + 1 }
            }
        }
    }
}

// MARK: - Glitch

private struct GlitchThresholdCalculatorView: View {
    let edition: Edition
    let diceRules: DiceHouseRules
    @State private var pool: Int
    @State private var ones = 0

    init(edition: Edition, diceRules: DiceHouseRules, initialPool: Int = 12) {
        self.edition = edition
        self.diceRules = diceRules
        _pool = State(initialValue: max(0, min(40, initialPool)))
    }

    private var result: GlitchThresholdCalculator.Result {
        GlitchThresholdCalculator.evaluate(pool: pool, edition: edition, diceRules: diceRules)
    }

    private var isGlitchNow: Bool {
        GlitchThresholdCalculator.isGlitch(ones: ones, pool: pool, edition: edition, diceRules: diceRules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Pool \(pool)", value: $pool, in: 0...40)
                .font(.caption)
            Stepper("Ones rolled \(ones)", value: $ones, in: 0...max(0, pool))
                .font(.caption)

            CalcResultLine(title: "Mode", value: result.mode.displayName)
            CalcResultLine(title: "Ones to glitch", value: pool == 0 ? "—" : "\(result.onesNeeded)+", emphasize: true)
            Text(result.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
            CalcResultLine(
                title: "This roll",
                value: pool == 0 ? "—" : (isGlitchNow ? "Glitch" : "No glitch")
            )
            Text("Hits on \(diceRules.hitMinimum)+ · \(edition.shortName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onChange(of: pool) { _, new in
            Task { @MainActor in
                if ones > new { ones = new }
            }
        }
    }
}

// MARK: - Lifestyle

private struct LifestyleBurnCalculatorView: View {
    @State private var level: LifestyleLevel = .middle
    @State private var count = 1
    @State private var customCost: Int
    @State private var useCustom: Bool

    init(initialMonthly: Int = 0) {
        if initialMonthly > 0 {
            _useCustom = State(initialValue: true)
            _customCost = State(initialValue: initialMonthly)
            _count = State(initialValue: 1)
        } else {
            _useCustom = State(initialValue: false)
            _customCost = State(initialValue: 0)
        }
    }

    private var total: Int {
        if useCustom {
            return max(0, customCost) * max(1, count)
        }
        return LifestyleBurnCalculator.suggestedMonthlyCost(level: level) * max(1, count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Custom monthly cost", isOn: $useCustom)
                .font(.caption)
            if useCustom {
                HStack {
                    Text("¥ / month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Cost", value: $customCost, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            } else {
                Picker("Level", selection: $level) {
                    ForEach(LifestyleLevel.allCases, id: \.self) { lv in
                        Text("\(lv.displayName) (¥\(lv.suggestedMonthlyCostSR5.formatted()))")
                            .tag(lv)
                    }
                }
                .font(.caption)
                Text("Suggested SR5-oriented amounts — edit on the character for real costs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Stepper("Lifestyles × \(count)", value: $count, in: 1...6)
                .font(.caption)
            CalcResultLine(title: "Monthly burn", value: "¥\(total.formatted())", emphasize: true)
        }
    }
}

// MARK: - Condition monitors

private struct ConditionMonitorCalculatorView: View {
    @State private var bodyRating: Int
    @State private var willpower: Int

    init(initialBody: Int = 3, initialWillpower: Int = 3) {
        _bodyRating = State(initialValue: max(1, min(12, initialBody)))
        _willpower = State(initialValue: max(1, min(12, initialWillpower)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Body \(bodyRating)", value: $bodyRating, in: 1...12)
                .font(.caption)
            Stepper("Willpower \(willpower)", value: $willpower, in: 1...12)
                .font(.caption)
            CalcResultLine(
                title: "Physical boxes",
                value: "\(ConditionMonitorCalculator.physicalBoxes(body: bodyRating))",
                emphasize: true
            )
            CalcResultLine(
                title: "Stun boxes",
                value: "\(ConditionMonitorCalculator.stunBoxes(willpower: willpower))",
                emphasize: true
            )
            Text("8 + ⌈Attr/2⌉")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - SR5 limits

private struct LimitsSR5CalculatorView: View {
    @State private var bodyRating: Int
    @State private var reaction: Int
    @State private var strength: Int
    @State private var willpower: Int
    @State private var logic: Int
    @State private var intuition: Int
    @State private var charisma: Int
    @State private var essence: Double

    init(context: RulesCalcContext = .neutral) {
        _bodyRating = State(initialValue: context.body)
        _reaction = State(initialValue: context.reaction)
        _strength = State(initialValue: context.strength)
        _willpower = State(initialValue: context.willpower)
        _logic = State(initialValue: context.logic)
        _intuition = State(initialValue: context.intuition)
        _charisma = State(initialValue: context.charisma)
        _essence = State(initialValue: context.essence)
    }

    private var result: LimitsSR5Calculator.Result {
        LimitsSR5Calculator.evaluate(
            body: bodyRating,
            reaction: reaction,
            strength: strength,
            willpower: willpower,
            logic: logic,
            intuition: intuition,
            charisma: charisma,
            essence: Decimal(essence)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SR5 only — other editions ignore this trio.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 4) {
                attrStepper("BOD", $bodyRating)
                attrStepper("REA", $reaction)
                attrStepper("STR", $strength)
                attrStepper("WIL", $willpower)
                attrStepper("LOG", $logic)
                attrStepper("INT", $intuition)
                attrStepper("CHA", $charisma)
            }
            HStack {
                Text("Essence")
                    .font(.caption)
                Slider(value: $essence, in: 0...6, step: 0.1)
                Text(String(format: "%.1f", essence))
                    .font(.caption.monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
            }
            CalcResultLine(title: "Physical", value: "\(result.physical)", emphasize: true)
            CalcResultLine(title: "Mental", value: "\(result.mental)", emphasize: true)
            CalcResultLine(title: "Social", value: "\(result.social)", emphasize: true)
        }
    }

    private func attrStepper(_ label: String, _ value: Binding<Int>) -> some View {
        Stepper("\(label) \(value.wrappedValue)", value: value, in: 1...12)
            .font(.caption2)
    }
}

// MARK: - Drain

private struct DrainCalculatorView: View {
    @State private var force: Int
    @State private var code: DrainCodeTemplate = .halfForcePlus2
    @State private var damageType: DrainDamageType = .stun
    @State private var willpower: Int
    @State private var traditionAttr: Int
    @State private var showResist = true

    init(initialForce: Int = 6, initialWillpower: Int = 4, initialTradition: Int = 4) {
        _force = State(initialValue: max(1, min(12, initialForce > 0 ? initialForce : 6)))
        _willpower = State(initialValue: max(1, min(12, initialWillpower)))
        _traditionAttr = State(initialValue: max(1, min(12, initialTradition)))
    }

    private var result: DrainCalculatorResult {
        DrainCalculator.evaluate(
            force: force,
            code: code,
            damageType: damageType,
            willpower: showResist ? willpower : nil,
            traditionAttribute: showResist ? traditionAttr : nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickAidBanner()
            Stepper("Force \(force)", value: $force, in: 1...16)
                .font(.caption)
            Picker("Drain code", selection: $code) {
                ForEach(DrainCodeTemplate.allCases) { c in
                    Text(c.displayName).tag(c)
                }
            }
            .font(.caption)
            Picker("Type", selection: $damageType) {
                ForEach(DrainDamageType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)

            CalcResultLine(title: "Drain value", value: "\(result.drainValue) \(result.damageType.displayName)", emphasize: true)

            Toggle("Resist pool hint", isOn: $showResist)
                .font(.caption)
            if showResist {
                HStack {
                    Stepper("WIL \(willpower)", value: $willpower, in: 1...12)
                    Stepper("Trad. \(traditionAttr)", value: $traditionAttr, in: 1...12)
                }
                .font(.caption2)
                if let pool = result.resistPoolHint {
                    CalcResultLine(title: "Resist pool", value: "\(pool) dice")
                }
            }
        }
    }
}

// MARK: - Overwatch

private struct OverwatchCalculatorView: View {
    @State private var score = 0
    @State private var threshold = OverwatchCalculator.defaultGODThreshold
    @State private var lastAction: String = ""

    private var snap: OverwatchSnapshot {
        OverwatchCalculator.snapshot(score: score, threshold: threshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickAidBanner()
            HStack {
                Stepper("OS \(score)", value: $score, in: 0...80)
                Stepper("GOD @ \(threshold)", value: $threshold, in: 20...60)
            }
            .font(.caption)

            CalcResultLine(
                title: "Status",
                value: snap.converged ? "Convergence!" : "\(snap.remainingToConvergence) to GOD",
                emphasize: true
            )

            Text("Add action")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowOSActions { action in
                score = OverwatchCalculator.apply(score: score, action: action)
                lastAction = "+\(action.osCost) \(action.name)"
            }

            if !lastAction.isEmpty {
                Text(lastAction)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button("Reset OS") {
                score = 0
                lastAction = ""
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
}

private struct FlowOSActions: View {
    var onPick: (OverwatchAction) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(OverwatchCalculator.defaultActions) { action in
                Button {
                    onPick(action)
                } label: {
                    Text("\(action.name) (+\(action.osCost))")
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(action.note.isEmpty ? "+\(action.osCost) OS" : action.note)
            }
        }
    }
}
