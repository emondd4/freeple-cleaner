import Foundation

enum RemapError: LocalizedError {
    case volumeMissing
    case notEnoughSpace(needed: Int64, free: Int64)
    case alreadyRemapped
    case notRemappable
    case sourceMissing
    case copyFailed(String)
    case unlinkFailed(String)
    case nothingMoved(String)

    var errorDescription: String? {
        switch self {
        case .volumeMissing: return "Selected volume is not mounted."
        case .notEnoughSpace(let needed, let free):
            return "Not enough free space on the SSD. Need \(ByteCount.string(needed)), have \(ByteCount.string(free))."
        case .alreadyRemapped: return "This category is already remapped."
        case .notRemappable: return "This category cannot be remapped."
        case .sourceMissing: return "Source folder does not exist."
        case .copyFailed(let m): return "Failed to move data: \(m)"
        case .unlinkFailed(let m): return "Failed to restore original folder: \(m)"
        case .nothingMoved(let m): return m
        }
    }
}

struct RemapOutcome {
    var record: RemapRecord
    var warnings: [String]
}

actor RemapService {
    private var store: RemapStore

    init() {
        store = RemapStore.load()
    }

    func records() -> [RemapRecord] {
        store.records
    }

    func remappedCategoryIDs() -> Set<String> {
        Set(store.records.map(\.categoryRaw))
    }

    func refreshStore() {
        store = RemapStore.load()
    }

    func remap(
        kind: CategoryKind,
        to volume: DiskVolume,
        byteSize: Int64
    ) async throws -> RemapOutcome {
        guard kind.canRemap else { throw RemapError.notRemappable }
        guard store.records.contains(where: { $0.categoryRaw == kind.rawValue }) == false else {
            throw RemapError.alreadyRemapped
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: volume.path) else { throw RemapError.volumeMissing }
        if volume.freeBytes > 0 && byteSize > 0 && byteSize > volume.freeBytes {
            throw RemapError.notEnoughSpace(needed: byteSize, free: volume.freeBytes)
        }

        guard let raw = kind.paths.first else { throw RemapError.sourceMissing }
        let source = PathSafety.expand(raw)
        guard fm.fileExists(atPath: source) else { throw RemapError.sourceMissing }
        guard PathSafety.isInsideHome(source) else { throw RemapError.notRemappable }

        if PathSafety.isSymlink(source) {
            throw RemapError.alreadyRemapped
        }

        let dest = URL(fileURLWithPath: volume.path)
            .appendingPathComponent("MacCleanerData", isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)

        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Resume / clean incomplete prior attempts that left a real folder (not a finished remap).
        if fm.fileExists(atPath: dest.path), !store.records.contains(where: { $0.destinationPath == dest.path }) {
            try? removeTreeBestEffort(dest.path)
        }

        let warnings: [String]
        let movedBytes: Int64

        if kind.remapsChildrenIndependently {
            let result = try remapChildren(of: source, to: dest.path)
            warnings = result.warnings
            movedBytes = result.movedBytes
            if result.movedCount == 0 {
                throw RemapError.nothingMoved(
                    result.warnings.first
                        ?? "Could not move any cache folders. Grant Freeple Cleaner Full Disk Access in System Settings → Privacy & Security, then retry."
                )
            }
        } else {
            try remapWholeFolder(from: source, to: dest.path)
            warnings = []
            movedBytes = byteSize
        }

        let record = RemapRecord(
            id: UUID().uuidString,
            categoryRaw: kind.rawValue,
            originalPath: source,
            destinationPath: dest.path,
            volumePath: volume.path,
            volumeName: volume.name,
            createdAt: Date(),
            bytesMoved: movedBytes,
            mode: kind.remapsChildrenIndependently ? .children : .wholeFolder
        )
        store.records.append(record)
        try store.save()
        return RemapOutcome(record: record, warnings: warnings)
    }

    func unmap(_ record: RemapRecord) async throws {
        let fm = FileManager.default
        let source = record.originalPath
        let dest = record.destinationPath

        guard fm.fileExists(atPath: record.volumePath) else {
            throw RemapError.volumeMissing
        }
        guard fm.fileExists(atPath: dest) else {
            throw RemapError.sourceMissing
        }

        if record.mode == .children || (!PathSafety.isSymlink(source) && directoryHasChildSymlinks(source, pointingInto: dest)) {
            try unmapChildren(of: source, from: dest)
        } else {
            if PathSafety.isSymlink(source) || fm.fileExists(atPath: source) {
                do {
                    try fm.removeItem(atPath: source)
                } catch {
                    throw RemapError.unlinkFailed(error.localizedDescription)
                }
            }
            do {
                try moveReplacing(from: dest, to: source)
            } catch {
                try? fm.createSymbolicLink(atPath: source, withDestinationPath: dest)
                throw RemapError.copyFailed(error.localizedDescription)
            }
        }

        let parent = URL(fileURLWithPath: dest).deletingLastPathComponent()
        if let kids = try? fm.contentsOfDirectory(atPath: parent.path), kids.isEmpty {
            try? fm.removeItem(at: parent)
        }

        store.records.removeAll { $0.id == record.id }
        try store.save()
    }

    // MARK: - Strategies

    /// Move/link each top-level child. Used for ~/Library/Caches where some Apple folders are TCC-locked.
    private func remapChildren(of source: String, to dest: String) throws -> (movedCount: Int, movedBytes: Int64, warnings: [String]) {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)

        let children = try fm.contentsOfDirectory(atPath: source)
        var moved = 0
        var bytes: Int64 = 0
        var warnings: [String] = []

        for name in children {
            let from = (source as NSString).appendingPathComponent(name)
            let to = (dest as NSString).appendingPathComponent(name)

            if PathSafety.isSymlink(from) {
                // Already linked; skip.
                continue
            }

            // Estimate size cheaply for bookkeeping.
            let childSize = approximateSize(at: from)

            do {
                if fm.fileExists(atPath: to) {
                    try removeTreeBestEffort(to)
                }
                try moveReplacing(from: from, to: to)
                // Replace original path with symlink to SSD copy.
                if fm.fileExists(atPath: from) {
                    try removeTreeBestEffort(from)
                }
                try fm.createSymbolicLink(atPath: from, withDestinationPath: to)
                moved += 1
                bytes += childSize
            } catch {
                warnings.append("Skipped \(name): \(shortError(error))")
                // If copy partially landed, clean dest child so retry is clean.
                if fm.fileExists(atPath: to), !fm.fileExists(atPath: from) {
                    // Data only on dest but no symlink — try to put symlink anyway.
                    try? fm.createSymbolicLink(atPath: from, withDestinationPath: to)
                    if PathSafety.isSymlink(from) {
                        moved += 1
                        bytes += childSize
                        warnings.removeLast()
                    }
                } else if fm.fileExists(atPath: to), fm.fileExists(atPath: from) {
                    try? removeTreeBestEffort(to)
                }
            }
        }

        if !warnings.isEmpty {
            warnings.append(
                "Protected Apple cache folders stay on the internal disk. Grant Full Disk Access to move more of them."
            )
        }

        return (moved, bytes, warnings)
    }

    private func remapWholeFolder(from source: String, to dest: String) throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: dest) {
            let backup = source + ".mac-cleaner-backup-\(Int(Date().timeIntervalSince1970))"
            try fm.moveItem(atPath: source, toPath: backup)
            do {
                try fm.createSymbolicLink(atPath: source, withDestinationPath: dest)
                try? removeTreeBestEffort(backup)
            } catch {
                try? fm.removeItem(atPath: source)
                try? fm.moveItem(atPath: backup, toPath: source)
                throw RemapError.copyFailed(error.localizedDescription)
            }
            return
        }

        do {
            try moveReplacing(from: source, to: dest)
            try fm.createSymbolicLink(atPath: source, withDestinationPath: dest)
        } catch {
            if !fm.fileExists(atPath: source), fm.fileExists(atPath: dest) {
                // Prefer linking over a destructive rollback across volumes.
                do {
                    try fm.createSymbolicLink(atPath: source, withDestinationPath: dest)
                    return
                } catch {
                    try? moveReplacing(from: dest, to: source)
                }
            }
            throw RemapError.copyFailed(shortError(error))
        }
    }

    private func unmapChildren(of source: String, from dest: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: source, withIntermediateDirectories: true)

        let destChildren = (try? fm.contentsOfDirectory(atPath: dest)) ?? []
        var failures: [String] = []

        for name in destChildren {
            let linkPath = (source as NSString).appendingPathComponent(name)
            let dataPath = (dest as NSString).appendingPathComponent(name)

            do {
                if PathSafety.isSymlink(linkPath) {
                    try fm.removeItem(atPath: linkPath)
                } else if fm.fileExists(atPath: linkPath) {
                    // Local leftover + SSD copy: prefer keeping SSD data by replacing local.
                    try removeTreeBestEffort(linkPath)
                }
                try moveReplacing(from: dataPath, to: linkPath)
            } catch {
                // Restore symlink if we removed it.
                if !fm.fileExists(atPath: linkPath), fm.fileExists(atPath: dataPath) {
                    try? fm.createSymbolicLink(atPath: linkPath, withDestinationPath: dataPath)
                }
                failures.append("\(name): \(shortError(error))")
            }
        }

        if fm.fileExists(atPath: dest) {
            let leftover = (try? fm.contentsOfDirectory(atPath: dest)) ?? []
            if leftover.isEmpty {
                try? fm.removeItem(atPath: dest)
            }
        }

        if !failures.isEmpty {
            throw RemapError.unlinkFailed(failures.joined(separator: "\n"))
        }
    }

    // MARK: - File helpers

    private func moveReplacing(from: String, to: String) throws {
        let fm = FileManager.default
        let fromURL = URL(fileURLWithPath: from)
        let toURL = URL(fileURLWithPath: to)

        if fm.fileExists(atPath: to) {
            try removeTreeBestEffort(to)
        }

        try fm.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            try fm.moveItem(at: fromURL, to: toURL)
        } catch {
            // Cross-volume or busy files: copy children resiliently, then remove source.
            try resilientCopy(from: from, to: to)
            try removeTreeBestEffort(from)
        }
    }

    /// Copy that continues when individual entries are permission-denied.
    private func resilientCopy(from: String, to: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: from, isDirectory: &isDir) else {
            throw RemapError.sourceMissing
        }

        if !isDir.boolValue {
            try fm.copyItem(atPath: from, toPath: to)
            return
        }

        try fm.createDirectory(atPath: to, withIntermediateDirectories: true)

        // Prefer ditto — preserves resource forks better; ignore its non-zero if some files denied.
        if runDitto(from: from, to: to) {
            return
        }

        let children = try fm.contentsOfDirectory(atPath: from)
        var copiedAny = false
        var lastError: Error?

        for name in children {
            let childFrom = (from as NSString).appendingPathComponent(name)
            let childTo = (to as NSString).appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: childTo) {
                    try removeTreeBestEffort(childTo)
                }
                try fm.copyItem(atPath: childFrom, toPath: childTo)
                copiedAny = true
            } catch {
                lastError = error
                // Nested directory: try resilient recursion.
                var childIsDir: ObjCBool = false
                if fm.fileExists(atPath: childFrom, isDirectory: &childIsDir), childIsDir.boolValue {
                    do {
                        try resilientCopy(from: childFrom, to: childTo)
                        copiedAny = true
                    } catch {
                        lastError = error
                    }
                }
            }
        }

        if !copiedAny, let lastError {
            throw lastError
        }
    }

    private func runDitto(from: String, to: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [from, to]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            // ditto returns 0 even when some TCC files are skipped; verify dest exists.
            return FileManager.default.fileExists(atPath: to) && process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func removeTreeBestEffort(_ path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        do {
            try fm.removeItem(atPath: path)
        } catch {
            // chmod -R u+w then retry via rm
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/rm")
            process.arguments = ["-rf", path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            if fm.fileExists(atPath: path) {
                throw error
            }
        }
    }

    private func directoryHasChildSymlinks(_ path: String, pointingInto dest: String) -> Bool {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        for name in children {
            let child = (path as NSString).appendingPathComponent(name)
            guard PathSafety.isSymlink(child) else { continue }
            if let destPath = try? fm.destinationOfSymbolicLink(atPath: child),
               destPath.hasPrefix(dest) {
                return true
            }
        }
        return false
    }

    private func approximateSize(at path: String) -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8),
                  let first = text.split(whereSeparator: { $0.isWhitespace }).first,
                  let kb = Int64(first) else { return 0 }
            return kb * 1024
        } catch {
            return 0
        }
    }

    private func shortError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == 1 {
            return "Operation not permitted (needs Full Disk Access)"
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == 1 {
            return "Operation not permitted (needs Full Disk Access)"
        }
        return error.localizedDescription
    }
}
