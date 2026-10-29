import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(alignment: .top, spacing: 16) {
                    metricCard(
                        title: "Macintosh HD free",
                        value: ByteCount.string(app.bootFree),
                        detail: app.bootTotal > 0
                            ? "\(Int(Double(app.bootFree) / Double(app.bootTotal) * 100))% available"
                            : "Scanning…",
                        tint: Theme.accent
                    )
                    metricCard(
                        title: "Reclaimable data",
                        value: ByteCount.string(app.reclaimableBytes),
                        detail: "\(app.categories.filter(\.exists).count) categories found",
                        tint: Theme.accentBlue
                    )
                    metricCard(
                        title: "Active remaps",
                        value: "\(app.remaps.count)",
                        detail: app.remaps.isEmpty ? "Nothing on external SSD" : "Linked to portable storage",
                        tint: Color(red: 0.55, green: 0.42, blue: 0.28)
                    )
                }

                diskBar
                topOffenders

                HStack(spacing: 12) {
                    Button {
                        app.section = .clean
                    } label: {
                        Label("Clean system data", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)

                    Button {
                        app.section = .remap
                    } label: {
                        Label("Remap to portable SSD", systemImage: "externaldrive")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundStyle(Theme.ink)
                }

                if let error = app.lastError, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Theme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overview")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Clear reclaimable system data, or move bulky folders onto a portable SSD with symlinks.")
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricCard(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground())
    }

    private var diskBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Internal storage")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            GeometryReader { geo in
                let usedFrac = app.bootTotal > 0 ? Double(app.bootTotal - app.bootFree) / Double(app.bootTotal) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardStroke.opacity(0.55))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * usedFrac))
                }
            }
            .frame(height: 10)

            Text("\(ByteCount.string(max(0, app.bootTotal - app.bootFree))) used · \(ByteCount.string(app.bootFree)) free")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .background(Theme.cardBackground())
    }

    private var topOffenders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest categories")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            let top = Array(app.categories.filter { $0.exists && $0.byteSize > 0 }.prefix(5))
            if top.isEmpty {
                Text(app.isScanning ? "Scanning…" : "No reclaimable data found yet. Run a scan.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(top) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.systemImage)
                            .foregroundStyle(item.kind.accent)
                            .frame(width: 24)
                        Text(item.kind.title)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if item.isRemapped {
                            Text("Remapped")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(red: 0.45, green: 0.32, blue: 0.18))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.55, green: 0.42, blue: 0.28).opacity(0.18), in: Capsule())
                        }
                        Text(item.sizeLabel)
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .background(Theme.cardBackground())
    }
}
