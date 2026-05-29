import SwiftUI

/// Green→yellow→red by how full a usage window is.
func usageColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.7: return .green
    case ..<0.9: return .yellow
    default: return .red
    }
}

func usagePercentText(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}

/// Human "2h 13m" until the given epoch, or nil if unknown/past.
func resetCountdown(_ epoch: Int64?) -> String? {
    guard let epoch, epoch > 0 else { return nil }
    let delta = Date(timeIntervalSince1970: TimeInterval(epoch)).timeIntervalSinceNow
    if delta <= 0 { return "resetting" }
    let total = Int(delta)
    let h = total / 3600
    let m = (total % 3600) / 60
    if h >= 1 { return "\(h)h \(m)m" }
    if m >= 1 { return "\(m)m" }
    return "<1m"
}

/// A thin progress bar for one usage window.
struct UsageMeter: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(fraction, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(usageColor(fraction))
                    .frame(width: max(2, geo.size.width * clamped))
            }
        }
        .frame(height: height)
    }
}

/// "rate limited" badge.
struct RateLimitedPill: View {
    var text = "rate limited"
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.red.opacity(0.16), in: Capsule())
            .foregroundStyle(.red)
    }
}

/// Compact two-line meter (5h + weekly) for the menu-bar dropdown.
struct CompactUsageView: View {
    let usage: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let five = usage.fiveHour { row("5h", five) }
            if let seven = usage.sevenDay { row("7d", seven) }
        }
    }

    private func row(_ label: String, _ window: UsageWindow) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            UsageMeter(fraction: window.utilization, height: 5)
            Text(usagePercentText(window.utilization))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

/// Full labeled meters with reset countdowns for Settings → Accounts.
struct DetailedUsageView: View {
    let usage: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let five = usage.fiveHour { window("Session (5h)", five) }
            if let seven = usage.sevenDay { window("Weekly (7d)", seven) }
        }
    }

    private func window(_ title: String, _ w: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(usagePercentText(w.utilization))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(usageColor(w.utilization))
                if let r = resetCountdown(w.reset) {
                    Text("· resets in \(r)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            UsageMeter(fraction: w.utilization, height: 7)
        }
    }
}
