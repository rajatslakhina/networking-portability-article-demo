import SwiftUI
import PortabilityCore

/// The demo screen. Shows the gap between what a team says its networking
/// coupling is and what the inventory actually says, and lets you change one
/// input at a time to watch the verdict move.
@available(iOS 17.0, macOS 14.0, *)
public struct PortabilityReportView: View {

    @State private var usages: [CapabilityUsage]
    @State private var showOnlyBlockers = false

    private let analyzer = PortabilityAnalyzer()

    public init(usages: [CapabilityUsage] = SampleInventory.usages) {
        _usages = State(initialValue: usages)
    }

    private var report: PortabilityReport {
        analyzer.analyze(declaredSeams: SampleInventory.declaredSeams, usages: usages)
    }

    public var body: some View {
        NavigationStack {
            List {
                headline
                verdictSection
                costSection
                inventorySection
            }
            .navigationTitle("Transport Surface")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(showOnlyBlockers ? "Show all" : "Blockers") {
                        showOnlyBlockers.toggle()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headline: some View {
        Section {
            HStack(spacing: 0) {
                metric(
                    value: "\(report.declaredSeams)",
                    caption: "declared seams",
                    tint: .secondary
                )
                Divider()
                metric(
                    value: "\(report.effectiveSurface)",
                    caption: "real capabilities",
                    tint: .orange
                )
                Divider()
                metric(
                    value: "\(report.bypassSiteCount)",
                    caption: "bypass sites",
                    tint: .red
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } footer: {
            Text("One protocol. \(report.effectiveSurface) behaviours behind it.")
        }
    }

    private var verdictSection: some View {
        Section("Verdict") {
            HStack {
                Image(systemName: verdictIcon)
                    .foregroundStyle(verdictTint)
                Text(report.verdict.label)
                    .font(.headline.monospaced())
                    .foregroundStyle(verdictTint)
                Spacer()
                Text("cost \(report.migrationCost, format: .number.precision(.fractionLength(0)))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(report.verdict.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var costSection: some View {
        Section("Where the cost actually sits") {
            let byClass = report.costByClass()
            let total = max(report.migrationCost, 0.0001)
            ForEach(PortabilityClass.allCases, id: \.self) { portabilityClass in
                let cost = byClass[portabilityClass] ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(portabilityClass.displayName).font(.subheadline)
                        Spacer()
                        Text("\(Int((cost / total) * 100))%")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(cost / total, 1))
                        .tint(tint(for: portabilityClass))
                    Text(portabilityClass.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var inventorySection: some View {
        Section("Inventory — tap a row to give it a fallback plan") {
            ForEach(visibleUsages) { usage in
                Button {
                    promote(usage)
                } label: {
                    row(for: usage)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var visibleUsages: [CapabilityUsage] {
        guard showOnlyBlockers else { return usages }
        return usages.filter {
            $0.capability.portability == .platformService && $0.fallback == .none
        }
    }

    // MARK: - Row

    private func row(for usage: CapabilityUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(tint(for: usage.capability.portability))
                    .frame(width: 8, height: 8)
                Text(usage.capability.name).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(usage.siteCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(usage.capability.rationale)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Label(
                    usage.routing == .bypassesSeam ? "bypasses seam" : "through seam",
                    systemImage: usage.routing == .bypassesSeam
                        ? "arrow.triangle.branch" : "arrow.right"
                )
                .font(.caption2)
                .foregroundStyle(usage.routing == .bypassesSeam ? .red : .secondary)
                Text("·").font(.caption2).foregroundStyle(.secondary)
                Text(usage.fallback.summary)
                    .font(.caption2)
                    .foregroundStyle(usage.fallback == .none ? .red : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Tapping a row upgrades its fallback plan one step. This is the whole
    /// interaction: watch a BLOCKED verdict become STAGEABLE by planning the
    /// platform services, without touching the protocol abstraction at all.
    private func promote(_ usage: CapabilityUsage) {
        guard let index = usages.firstIndex(where: { $0.id == usage.id }) else { return }
        let next: FallbackPlan
        switch usages[index].fallback {
        case .none:
            next = .documented("plan drafted in-app")
        case .documented:
            next = .implemented("built and shipping")
        case .implemented:
            next = .none
        }
        usages[index] = CapabilityUsage(
            capability: usages[index].capability,
            module: usages[index].module,
            siteCount: usages[index].siteCount,
            routing: usages[index].routing,
            fallback: next
        )
    }

    // MARK: - Presentation helpers

    private func metric(value: String, caption: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title.monospacedDigit().bold()).foregroundStyle(tint)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tint(for portabilityClass: PortabilityClass) -> Color {
        switch portabilityClass {
        case .currencyType: return .green
        case .protocolLayer: return .yellow
        case .platformService: return .red
        }
    }

    private var verdictTint: Color {
        switch report.verdict {
        case .cheap: return .green
        case .stageable: return .orange
        case .blocked: return .red
        }
    }

    private var verdictIcon: String {
        switch report.verdict {
        case .cheap: return "checkmark.seal.fill"
        case .stageable: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    PortabilityReportView()
}
