import SwiftUI

@main
struct MacCleanerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Navigate") {
                Button("Overview") { appState.section = .dashboard }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Clean") { appState.section = .clean }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Remap to SSD") { appState.section = .remap }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Settings") { appState.section = .settings }
                    .keyboardShortcut("4", modifiers: [.command])
            }
            CommandMenu("Clean") {
                Button("Scan Now") {
                    Task { await appState.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Clean Selected") {
                    Task { await appState.cleanSelected() }
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(!appState.canClean)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 420, height: 280)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var section: AppSection = .dashboard
    @Published var categories: [CategoryScan] = []
    @Published var remaps: [RemapRecord] = []
    @Published var isScanning = false
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var lastError: String?
    @Published var bootTotal: Int64 = 0
    @Published var bootFree: Int64 = 0
    @Published var selectedVolumeID: String?
    @Published var confirmClean = false
    @Published var lastFreedBytes: Int64 = 0

    let volumes = VolumeMonitor()
    private let scanner = DiskScanner()
    private let cleaner = CleanerService()
    private let remapper = RemapService()

    var selectedCategories: [CategoryScan] {
        categories.filter(\.selected)
    }

    var selectedBytes: Int64 {
        selectedCategories.reduce(0) { $0 + $1.byteSize }
    }

    var reclaimableBytes: Int64 {
        categories.filter(\.exists).reduce(0) { $0 + $1.byteSize }
    }

    var canClean: Bool {
        !selectedCategories.isEmpty && !isWorking && !isScanning
    }

    var selectedVolume: DiskVolume? {
        volumes.volumes.first { $0.id == selectedVolumeID } ?? volumes.portableVolumes.first
    }

    var remappableCategories: [CategoryScan] {
        categories.filter { $0.kind.canRemap && $0.exists && !$0.isRemapped }
    }

    init() {
        Task { await initialLoad() }
    }

    private func initialLoad() async {
        await refreshRemaps()
        await scan()
        if selectedVolumeID == nil {
            selectedVolumeID = volumes.portableVolumes.first?.id
        }
    }

    func scan() async {
        isScanning = true
        lastError = nil
        statusMessage = "Scanning system data…"
        defer {
            isScanning = false
        }

        let remapped = await remapper.remappedCategoryIDs()
        let stats = await scanner.bootVolumeStats()
        bootTotal = stats.total
        bootFree = stats.free

        let previousSelection = Dictionary(uniqueKeysWithValues: categories.map { ($0.kind, $0.selected) })
        var scanned = await scanner.scanAll(remappedIDs: remapped)
        for i in scanned.indices {
            if let prev = previousSelection[scanned[i].kind] {
                scanned[i].selected = prev && scanned[i].exists && scanned[i].byteSize > 0
            }
        }
        categories = scanned
        statusMessage = "Scan complete — \(ByteCount.string(reclaimableBytes)) reclaimable"
    }

    func refreshRemaps() async {
        await remapper.refreshStore()
        remaps = await remapper.records()
    }

    func toggle(_ kind: CategoryKind) {
        guard let idx = categories.firstIndex(where: { $0.kind == kind }) else { return }
        categories[idx].selected.toggle()
    }

    func selectAllCleanable(_ on: Bool) {
        for i in categories.indices {
            if categories[i].exists && categories[i].byteSize > 0 && categories[i].kind.canClean {
                categories[i].selected = on
            }
        }
    }

    func cleanSelected() async {
        confirmClean = false
        let toClean = selectedCategories.map(\.kind)
        let sizes = Dictionary(uniqueKeysWithValues: selectedCategories.map { ($0.kind, $0.byteSize) })
        guard !toClean.isEmpty else { return }

        isWorking = true
        statusMessage = "Cleaning…"
        lastError = nil
        defer { isWorking = false }

        do {
            let report = try await cleaner.clean(categories: toClean, sizes: sizes)
            lastFreedBytes = report.freedBytes
            if report.warnings.isEmpty {
                statusMessage = "Freed about \(ByteCount.string(report.freedBytes))"
            } else {
                statusMessage = "Freed about \(ByteCount.string(report.freedBytes)) with warnings"
                lastError = report.warnings.joined(separator: "\n")
            }
            await scan()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Clean failed"
        }
    }

    func remap(_ kind: CategoryKind) async {
        guard let volume = selectedVolume else {
            lastError = "Plug in a portable SSD and select it in Remap."
            return
        }
        guard let category = categories.first(where: { $0.kind == kind }) else { return }

        isWorking = true
        statusMessage = "Moving \(kind.title) to \(volume.name)…"
        lastError = nil
        defer { isWorking = false }

        do {
            let outcome = try await remapper.remap(kind: kind, to: volume, byteSize: category.byteSize)
            await refreshRemaps()
            if outcome.warnings.isEmpty {
                statusMessage = "\(kind.title) remapped to \(volume.name)"
                lastError = nil
            } else {
                statusMessage = "\(kind.title) remapped with some folders skipped"
                lastError = outcome.warnings.joined(separator: "\n")
            }
            await scan()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Remap failed"
        }
    }

    func unmap(_ record: RemapRecord) async {
        isWorking = true
        statusMessage = "Restoring \(record.category?.title ?? "data") to internal disk…"
        lastError = nil
        defer { isWorking = false }

        do {
            try await remapper.unmap(record)
            await refreshRemaps()
            statusMessage = "Restored to internal disk"
            await scan()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Unmap failed"
        }
    }
}
