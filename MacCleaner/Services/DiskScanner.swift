import Foundation

actor DiskScanner {
    func scanAll(remappedIDs: Set<String>) async -> [CategoryScan] {
        var results: [CategoryScan] = []
        for kind in CategoryKind.allCases {
            let scan = await scan(kind: kind, isRemapped: remappedIDs.contains(kind.rawValue))
            results.append(scan)
        }
        return results.sorted { $0.byteSize > $1.byteSize }
    }

    func scan(kind: CategoryKind, isRemapped: Bool) async -> CategoryScan {
        let fm = FileManager.default
        var total: Int64 = 0
        var count = 0
        var anyExists = false

        for raw in kind.paths {
            let path = PathSafety.expand(raw)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            anyExists = true
            let (bytes, items) = directorySize(at: path)
            total += bytes
            count += items
        }

        return CategoryScan(
            id: kind,
            byteSize: total,
            itemCount: count,
            exists: anyExists,
            isRemapped: isRemapped,
            selected: anyExists && total > 0 && kind.canClean
        )
    }

    /// Fast approximate size using `du` when available; falls back to enumerator.
    private func directorySize(at path: String) -> (Int64, Int) {
        if let du = duSize(path: path) {
            let count = shallowItemCount(at: path)
            return (du, count)
        }
        return enumerateSize(at: path)
    }

    private func duSize(path: String) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8),
                  let first = text.split(whereSeparator: { $0.isWhitespace }).first,
                  let kb = Int64(first) else { return nil }
            return kb * 1024
        } catch {
            return nil
        }
    }

    private func shallowItemCount(at path: String) -> Int {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        return max(contents.count, 1)
    }

    private func enumerateSize(at path: String) -> (Int64, Int) {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var total: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            count += 1
        }
        return (total, count)
    }

    func bootVolumeStats() -> (total: Int64, free: Int64) {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else { return (0, 0) }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let freeImportant = values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
        let free = freeImportant ?? Int64(values.volumeAvailableCapacity ?? 0)
        return (total, free)
    }
}
