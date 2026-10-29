import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("App", value: "Freeple Cleaner")
                LabeledContent("Version", value: "1.0.0")
                Text("Cleans reclaimable user-level system data and can relocate bulky developer folders onto a portable SSD using symlinks.")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
            }

            Section("Safety") {
                Text("Only paths inside your home folder (plus Homebrew cache) are cleaned. System directories are never deleted. Remapped folders live under MacCleanerData on the chosen volume.")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
            }

            Section("Permissions") {
                Text("User Caches remap skips privacy-protected Apple folders unless Freeple Cleaner has Full Disk Access.")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                Button("Open Privacy & Security settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("Storage map") {
                LabeledContent("Remap database") {
                    Text(RemapStore.fileURL.path)
                        .font(.caption)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
                Button("Reveal remap database") {
                    NSWorkspace.shared.activateFileViewerSelecting([RemapStore.fileURL])
                }
            }

            Section("Actions") {
                Button("Rescan now") {
                    Task { await app.scan() }
                }
                Button("Refresh volumes") {
                    app.volumes.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
    }
}
