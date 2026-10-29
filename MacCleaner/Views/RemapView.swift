import SwiftUI

struct RemapView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                volumePicker
                activeRemaps
                availableRemaps
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remap to SSD")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Move bulky folders onto a portable drive and leave a symlink in place so apps keep working. Keep the SSD plugged in while those apps run.")
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var volumePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Portable volume")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    app.volumes.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accentBlue)
            }

            if app.volumes.portableVolumes.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(Theme.warn)
                    Text("No portable volumes detected. Connect an SSD and click Refresh.")
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(app.volumes.portableVolumes) { volume in
                    volumeRow(volume)
                }
            }
        }
        .padding(18)
        .background(Theme.cardBackground())
    }

    private func volumeRow(_ volume: DiskVolume) -> some View {
        let selected = app.selectedVolumeID == volume.id
        return Button {
            app.selectedVolumeID = volume.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "externaldrive")
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(volume.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(volume.path)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(volume.capacityLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                ProgressView(value: 1 - volume.freeFraction)
                    .frame(width: 80)
                    .tint(Theme.accent)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.12) : Theme.canvasTop.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Theme.accent.opacity(0.45) : Theme.cardStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var activeRemaps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active remaps")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            if app.remaps.isEmpty {
                Text("Nothing remapped yet.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(app.remaps) { record in
                    remapRecordRow(record)
                }
            }
        }
        .padding(18)
        .background(Theme.cardBackground())
    }

    private func remapRecordRow(_ record: RemapRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.isVolumeMounted ? "link" : "link.badge.plus")
                .foregroundStyle(record.isVolumeMounted ? Theme.accent : Theme.warn)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.category?.title ?? record.categoryRaw)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("→ \(record.destinationPath)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(record.volumeName)
                    Text("·")
                    Text(ByteCount.string(record.bytesMoved))
                    if !record.isVolumeMounted {
                        Text("· SSD unmounted")
                            .foregroundStyle(Theme.warn)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            }

            Spacer()

            Button("Restore") {
                Task { await app.unmap(record) }
            }
            .foregroundStyle(Theme.accentBlue)
            .disabled(app.isWorking || !record.isVolumeMounted)
            .help(record.isVolumeMounted ? "Move data back to the internal disk" : "Mount the SSD first")
        }
        .padding(.vertical, 6)
    }

    private var availableRemaps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available to remap")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            if app.remappableCategories.isEmpty {
                Text("No remappable categories with data, or everything is already remapped.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(app.remappableCategories) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.systemImage)
                            .foregroundStyle(item.kind.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.kind.title)
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text(item.kind.subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(item.sizeLabel)
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                        Button("Remap") {
                            Task { await app.remap(item.kind) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentBlue)
                        .disabled(app.isWorking || app.selectedVolume == nil)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.canvasTop.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
                            )
                    )
                }
            }

            if let error = app.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Theme.cardBackground())
    }
}
