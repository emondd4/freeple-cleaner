import Foundation
import AppKit

@MainActor
final class VolumeMonitor: ObservableObject {
    @Published private(set) var volumes: [DiskVolume] = []

    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]
        for name in names {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            workspaceObservers.append(token)
        }
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            nc.removeObserver(token)
        }
    }

    func refresh() {
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeIsInternalKey,
                .volumeIsEjectableKey,
                .volumeIsRemovableKey,
                .volumeUUIDStringKey
            ],
            options: [.skipHiddenVolumes]
        ) else {
            volumes = []
            return
        }

        var found: [DiskVolume] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeIsInternalKey,
                .volumeIsEjectableKey,
                .volumeIsRemovableKey,
                .volumeUUIDStringKey
            ])

            let name = values?.volumeName ?? url.lastPathComponent
            let total = Int64(values?.volumeTotalCapacity ?? 0)
            let freeImportant = values?.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
            let free = freeImportant ?? Int64(values?.volumeAvailableCapacity ?? 0)
            let isInternal = values?.volumeIsInternal ?? (url.path == "/" || url.path.hasPrefix("/System"))
            let isEjectable = values?.volumeIsEjectable ?? false
            let isRemovable = values?.volumeIsRemovable ?? false
            let uuid = values?.volumeUUIDString ?? url.path

            // Skip the boot volume and Time Machine locals that aren't useful remapping targets.
            if url.path == "/" { continue }
            if name.hasPrefix("com.apple.TimeMachine") { continue }

            found.append(
                DiskVolume(
                    id: uuid,
                    name: name,
                    path: url.path,
                    totalBytes: total,
                    freeBytes: free,
                    isInternal: isInternal,
                    isEjectable: isEjectable,
                    isRemovable: isRemovable
                )
            )
        }

        volumes = found.sorted { lhs, rhs in
            if lhs.isPortableCandidate != rhs.isPortableCandidate {
                return lhs.isPortableCandidate && !rhs.isPortableCandidate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var portableVolumes: [DiskVolume] {
        volumes.filter(\.isPortableCandidate)
    }
}
