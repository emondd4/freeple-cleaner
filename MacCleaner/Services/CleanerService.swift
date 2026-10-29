import Foundation

enum CleanerError: LocalizedError {
    case protectedPath(String)
    case nothingSelected
    case partialFailure([String])

    var errorDescription: String? {
        switch self {
        case .protectedPath(let p): return "Refusing to clean protected path: \(p)"
        case .nothingSelected: return "Select at least one category to clean."
        case .partialFailure(let msgs): return msgs.joined(separator: "\n")
        }
    }
}

struct CleanReport {
    var freedBytes: Int64
    var categoriesCleared: [CategoryKind]
    var warnings: [String]
}

actor CleanerService {
    func clean(categories: [CategoryKind], sizes: [CategoryKind: Int64]) async throws -> CleanReport {
        guard !categories.isEmpty else { throw CleanerError.nothingSelected }

        var freed: Int64 = 0
        var cleared: [CategoryKind] = []
        var warnings: [String] = []
        let fm = FileManager.default

        for kind in categories {
            var categoryFreed: Int64 = 0
            let expected = sizes[kind] ?? 0

            for raw in kind.paths {
                let path = PathSafety.expand(raw)

                if PathSafety.isProtected(path) && kind != .temporaryFiles {
                    warnings.append("Skipped protected path \(path)")
                    continue
                }

                // Never delete the entire home directory or system roots.
                guard PathSafety.isInsideHome(path)
                        || path.hasPrefix(NSTemporaryDirectory())
                        || path.hasPrefix("/opt/homebrew/var/cache")
                        || path.hasPrefix("/private/var/folders") else {
                    warnings.append("Skipped out-of-scope path \(path)")
                    continue
                }

                guard fm.fileExists(atPath: path) else { continue }

                if PathSafety.isSymlink(path) {
                    warnings.append("\(kind.title) looks remapped (symlink). Unmap before cleaning, or clean on the SSD.")
                    continue
                }

                do {
                    try emptyContents(of: path, kind: kind)
                    categoryFreed = expected
                } catch {
                    warnings.append("\(kind.title): \(error.localizedDescription)")
                }
            }

            if categoryFreed > 0 || expected == 0 {
                freed += max(categoryFreed, 0)
                cleared.append(kind)
            }
        }

        if cleared.isEmpty && !warnings.isEmpty {
            throw CleanerError.partialFailure(warnings)
        }

        return CleanReport(freedBytes: freed, categoriesCleared: cleared, warnings: warnings)
    }

    /// Removes contents but keeps the directory itself (safer for caches that apps expect).
    private func emptyContents(of path: String, kind: CategoryKind) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return }

        if !isDir.boolValue {
            try fm.removeItem(atPath: path)
            return
        }

        // For Trash, emptying means removing each item.
        let url = URL(fileURLWithPath: path)
        let children = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )

        for child in children {
            // Skip our own remap store / app support accidentally under caches.
            if child.lastPathComponent == "MacCleaner" { continue }
            // Keep critical Apple cache roots' structure but clear contents.
            try removeItemBestEffort(child)
        }

        // DerivedData / Simulator: also fine to remove the folder and recreate.
        if kind == .xcodeDerivedData || kind == .coreSimulator || kind == .iosBackups {
            // Already emptied; recreate if missing.
            if !fm.fileExists(atPath: path) {
                try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
        }
    }

    private func removeItemBestEffort(_ url: URL) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: url)
        } catch {
            // Try deleting children first (permission quirks).
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let kids = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                for kid in kids {
                    try? fm.removeItem(at: kid)
                }
                try fm.removeItem(at: url)
            } else {
                throw error
            }
        }
    }
}
