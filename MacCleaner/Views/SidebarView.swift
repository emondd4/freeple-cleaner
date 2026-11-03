import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Freeple Cleaner")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Clean · Remap · Move apps")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    sidebarButton(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            if let status = app.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.cardStroke.opacity(0.7))
                .frame(width: 1)
        }
    }

    private func sidebarButton(_ section: AppSection) -> some View {
        let selected = app.section == section
        return Button {
            app.section = section
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Theme.sidebarSelected : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
