import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [Theme.canvasTop, Theme.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch app.section {
                    case .dashboard:
                        DashboardView()
                    case .clean:
                        CategoryListView()
                    case .remap:
                        RemapView()
                    case .settings:
                        SettingsView()
                    }
                }
                .padding(24)
                .foregroundStyle(Theme.ink)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
}
