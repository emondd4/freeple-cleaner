import SwiftUI
import AppKit

struct AppsView: View {
    @EnvironmentObject private var app: AppState
    @State private var filter: AppFilter = .movable
    @State private var query = ""

    private var filtered: [InstalledApp] {
        app.installedApps.filter { item in
            switch filter {
            case .movable: return !item.isAppleOrSystem
            case .onSSD: return item.isRemapped
            case .apple: return item.isAppleOrSystem
            case .all: return true
            }
        }
        .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            volumeStrip
            filterBar

            ScrollView {
                LazyVStack(spacing: 8) {
                    if filtered.isEmpty {
                        Text(app.isScanning ? "Scanning applications…" : "No apps match this filter.")
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    }

                    ForEach(filtered) { item in
                        appRow(item)
                    }

                    if !app.appRemaps.isEmpty && filter != .apple {
                        remappedSection
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let error = app.lastError, app.section == .apps {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Move Apps")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("NEW")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accentWarm, in: Capsule())
                }
                Text("Keep Apple & system apps on this Mac. Park third-party apps on your portable SSD — Launchpad still finds them.")
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(app.selectedMovableApps.count)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("selected · \(ByteCount.string(app.selectedAppsBytes))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var volumeStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.selectedVolume?.name ?? "No portable SSD selected")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(app.selectedVolume?.capacityLabel ?? "Plug in a drive, then pick it here.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if !app.volumes.portableVolumes.isEmpty {
                Picker("SSD", selection: Binding(
                    get: { app.selectedVolumeID ?? app.volumes.portableVolumes.first?.id ?? "" },
                    set: { app.selectedVolumeID = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(app.volumes.portableVolumes) { vol in
                        Text(vol.name).tag(vol.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Button {
                Task { await app.moveSelectedApps() }
            } label: {
                Label("Move to SSD", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!app.canMoveApps)
        }
        .padding(16)
        .background(Theme.cardBackground())
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            ForEach(AppFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(filter == item ? Theme.accent : Theme.chip, in: Capsule())
                        .foregroundStyle(filter == item ? Color.white : Theme.ink)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Button("Select movable") { app.selectMovableApps(true) }
                .foregroundStyle(Theme.accentBlue)
            Button("Clear") { app.selectMovableApps(false) }
                .foregroundStyle(Theme.accentBlue)
        }
    }

    private var remappedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On portable SSD")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(.top, 12)
            ForEach(app.appRemaps) { record in
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.appName).font(.headline).foregroundStyle(Theme.ink)
                        Text(record.destinationPath)
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(ByteCount.string(record.bytesMoved))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                    Button("Restore") {
                        Task { await app.restoreApp(record) }
                    }
                    .disabled(app.isWorking || !record.isVolumeMounted)
                }
                .padding(12)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func appRow(_ item: InstalledApp) -> some View {
        HStack(spacing: 12) {
            if !item.isAppleOrSystem && !item.isRemapped {
                Toggle("", isOn: Binding(
                    get: { item.selected },
                    set: { _ in app.toggleApp(item) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(app.isWorking)
            } else {
                Image(systemName: item.isAppleOrSystem ? "lock.fill" : "link")
                    .foregroundStyle(item.isAppleOrSystem ? Theme.muted : Theme.accent)
                    .frame(width: 20)
            }

            AppIconView(path: item.path)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if item.isAppleOrSystem {
                        Text("Apple / System")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.06), in: Capsule())
                    }
                    if item.isRemapped {
                        Text("On SSD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.chip, in: Capsule())
                    }
                }
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.sizeLabel)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground(radius: 12))
        .opacity(item.isAppleOrSystem ? 0.72 : 1)
    }
}

/// Loads workspace icons without blowing up LazyVStack layout.
private struct AppIconView: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case movable, onSSD, apple, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .movable: return "Third-party"
        case .onSSD: return "On SSD"
        case .apple: return "Apple (kept)"
        case .all: return "All"
        }
    }
}
