import SwiftUI

struct CategoryListView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clean")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Select categories of system data to delete. Remapped folders are skipped.")
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(ByteCount.string(app.selectedBytes))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text("selected")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            HStack {
                Button("Select all") { app.selectAllCleanable(true) }
                    .foregroundStyle(Theme.accentBlue)
                Button("Select none") { app.selectAllCleanable(false) }
                    .foregroundStyle(Theme.accentBlue)
                Spacer()
                Button {
                    app.confirmClean = true
                } label: {
                    Label("Clean selected", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
                .disabled(!app.canClean)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(app.categories) { item in
                        categoryRow(item)
                    }
                }
            }

            if let error = app.lastError, app.section == .clean {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private func categoryRow(_ item: CategoryScan) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Toggle("", isOn: Binding(
                get: { item.selected },
                set: { _ in app.toggle(item.kind) }
            ))
            .labelsHidden()
            .disabled(!item.exists || item.byteSize == 0 || item.isRemapped || app.isWorking)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.kind.accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(item.kind.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.kind.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if item.isRemapped {
                        Text("On SSD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 0.45, green: 0.32, blue: 0.18))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.55, green: 0.42, blue: 0.28).opacity(0.18), in: Capsule())
                    }
                }
                Text(item.kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                if let note = item.kind.riskNote, item.selected {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.sizeLabel)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if item.exists && item.itemCount > 0 {
                    Text("\(item.itemCount) items")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground())
        .opacity(item.exists ? 1 : 0.55)
    }
}
