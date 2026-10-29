import Foundation

enum PathSafety {
    /// Absolute paths that must never be deleted or remapped as a whole.
    private static let forbiddenExact: Set<String> = [
        "/",
        "/System",
        "/Library",
        "/Applications",
        "/Users",
        "/bin",
        "/sbin",
        "/usr",
        "/etc",
        "/var",
        "/private",
        NSHomeDirectory()
    ]

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func isProtected(_ path: String) -> Bool {
        let expanded = expand(path)
        if forbiddenExact.contains(expanded) { return true }
        if expanded.hasPrefix("/System/") { return true }
        if expanded == "/Library" || expanded.hasPrefix("/Library/") && !expanded.hasPrefix("/Library/Caches") {
            // Allow only known safe library subpaths via category allowlists.
        }
        return false
    }

    static func isInsideHome(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let expanded = expand(path)
        return expanded == home || expanded.hasPrefix(home + "/")
    }

    static func resolveSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: expand(path)).resolvingSymlinksInPath().path
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expand(path), isDirectory: &isDir) && isDir.boolValue
    }

    static func isSymlink(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: expand(path))
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink == true
    }
}
