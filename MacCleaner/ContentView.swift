import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)
                .frame(maxHeight: .infinity)

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Theme.canvasTop, Theme.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                detail
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.light)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if app.isScanning || app.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 6)
                }

                Button {
                    Task { await app.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(app.isScanning || app.isWorking)
                .help("Rescan system data")
            }
        }
        .alert("Clean selected categories?", isPresented: $app.confirmClean) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) {
                Task { await app.cleanSelected() }
            }
        } message: {
            Text("This permanently deletes about \(ByteCount.string(app.selectedBytes)) of data. Remapped folders are skipped.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.section {
        case .dashboard:
            DashboardView()
        case .clean:
            CategoryListView()
        case .remap:
            RemapView()
        case .apps:
            AppsView()
        case .settings:
            SettingsView()
        }
    }
}
