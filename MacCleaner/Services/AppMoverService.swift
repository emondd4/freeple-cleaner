import Foundation
import AppKit

enum AppMoverError: LocalizedError {
    case volumeMissing
    case notEnoughSpace(needed: Int64, free: Int64)
    case appleApp
    case alreadyRemapped
    case sourceMissing
    case moveFailed(String)
    case nothingSelected

    var errorDescription: String? {
        switch self {
        case .volumeMissing: return "Selected volume is not mounted."
        case .notEnoughSpace(let n, let f):
            return "Not enough free space. Need \(ByteCount.string(n)), have \(ByteCount.string(f))."
        case .appleApp: return "Apple and system apps stay on this Mac."
        case .alreadyRemapped: return "This app is already on the portable SSD."
        case .sourceMissing: return "App not found."
        case .moveFailed(let m): return m
        case .nothingSelected: return "Select at least one third-party app."
        }
    }
}

actor AppMoverService {
    private var store: AppRemapStore

    init() {
        store = AppRemapStore.load()
    }

    func records() -> [AppRemapRecord] { store.records }

    func remappedPaths() -> Set<String> {
        Set(store.records.map(\.originalPath))
    }

    func refreshStore() {
        store = AppRemapStore.load()
    }

    /// Scans /Applications and ~/Applications. Apple/system apps are flagged and not movable.
    func scanInstalledApps() async -> [InstalledApp] {
        let fm = FileManager.default
        let roots = [
            "/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        var found: [InstalledApp] = []
        let remapped = remappedPaths()

        for root in roots {
            guard let kids = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in kids where name.hasSuffix(".app") {
                let path = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }

                let url = URL(fileURLWithPath: path)
                let bundle = Bundle(url: url)
                let bid = bundle?.bundleIdentifier
                let display = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? (name as NSString).deletingPathExtension

                let apple = Self.isAppleOrSystemApp(path: path, bundleID: bid, bundle: bundle)
                let size = directorySize(path)
                let already = remapped.contains(path) || PathSafety.isSymlink(path)

                found.append(
                    InstalledApp(
                        id: path,
                        name: display,
                        path: path,
                        bundleIdentifier: bid,
                        byteSize: size,
                        isAppleOrSystem: apple,
                        isRemapped: already,
                        selected: false
                    )
                )
            }
        }

        return found.sorted {
            if $0.isAppleOrSystem != $1.isAppleOrSystem { return !$0.isAppleOrSystem && $1.isAppleOrSystem }
            if $0.isRemapped != $1.isRemapped { return $0.isRemapped && !$1.isRemapped }
            return $0.byteSize > $1.byteSize
        }
    }

    func moveApps(_ apps: [InstalledApp], to volume: DiskVolume) async throws -> (moved: Int, warnings: [String]) {
        guard !apps.isEmpty else { throw AppMoverError.nothingSelected }
        let fm = FileManager.default
        guard fm.fileExists(atPath: volume.path) else { throw AppMoverError.volumeMissing }

        let needed = apps.reduce(Int64(0)) { $0 + $1.byteSize }
        if volume.freeBytes > 0 && needed > volume.freeBytes {
            throw AppMoverError.notEnoughSpace(needed: needed, free: volume.freeBytes)
        }

        let destRoot = URL(fileURLWithPath: volume.path)
            .appendingPathComponent("MacCleanerData", isDirectory: true)
            .appendingPathComponent("Apps", isDirectory: true)
        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

        var moved = 0
        var warnings: [String] = []

        for app in apps {
            if app.isAppleOrSystem {
                warnings.append("Skipped Apple/system app: \(app.name)")
                continue
            }
            if store.records.contains(where: { $0.originalPath == app.path }) || PathSafety.isSymlink(app.path) {
                warnings.append("Already remapped: \(app.name)")
                continue
            }

            let dest = destRoot.appendingPathComponent((app.path as NSString).lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try moveReplacing(from: app.path, to: dest.path)
                try fm.createSymbolicLink(atPath: app.path, withDestinationPath: dest.path)

                let record = AppRemapRecord(
                    id: UUID().uuidString,
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    originalPath: app.path,
                    destinationPath: dest.path,
                    volumePath: volume.path,
                    volumeName: volume.name,
                    createdAt: Date(),
                    bytesMoved: app.byteSize
                )
                store.records.append(record)
                moved += 1
            } catch {
                warnings.append("\(app.name): \(error.localizedDescription)")
                if !fm.fileExists(atPath: app.path), fm.fileExists(atPath: dest.path) {
                    try? fm.createSymbolicLink(atPath: app.path, withDestinationPath: dest.path)
                }
            }
        }

        try store.save()
        if moved == 0 {
            throw AppMoverError.moveFailed(warnings.first ?? "No apps were moved.")
        }
        return (moved, warnings)
    }

    func restore(_ record: AppRemapRecord) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: record.volumePath) else { throw AppMoverError.volumeMissing }
        guard fm.fileExists(atPath: record.destinationPath) else { throw AppMoverError.sourceMissing }

        if PathSafety.isSymlink(record.originalPath) || fm.fileExists(atPath: record.originalPath) {
            try fm.removeItem(atPath: record.originalPath)
        }
        do {
            try moveReplacing(from: record.destinationPath, to: record.originalPath)
        } catch {
            try? fm.createSymbolicLink(atPath: record.originalPath, withDestinationPath: record.destinationPath)
            throw AppMoverError.moveFailed(error.localizedDescription)
        }

        store.records.removeAll { $0.id == record.id }
        try store.save()
    }

    // MARK: - Helpers

    static func isAppleOrSystemApp(path: String, bundleID: String?, bundle: Bundle?) -> Bool {
        if path.hasPrefix("/System/") { return true }
        if let bid = bundleID {
            let lower = bid.lowercased()
            if lower.hasPrefix("com.apple.") { return true }
            if lower.hasPrefix("com.apple.dt.") { return true }
        }
        // Signed by Apple
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=2", path]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                if text.contains("Authority=Software Signing")
                    || text.contains("Authority=Apple Mac OS Application Signing")
                    || text.contains("TeamIdentifier=Apple")
                    || text.contains("Authority=Apple Application Integration") {
                    // App Store Apple apps / system — still treat com.apple only for Authority apple
                    if text.contains("TeamIdentifier=59GAB85EFG") /* Apple */ ||
                        text.contains("Authority=Software Signing") {
                        if bundleID?.hasPrefix("com.apple.") == true { return true }
                    }
                    if text.contains("Authority=Software Signing") { return true }
                }
            }
        } catch {}

        // Known Apple app names in /Applications without reliable ID
        let appleNames: Set<String> = [
            "Safari.app", "Mail.app", "Photos.app", "Music.app", "TV.app", "Podcasts.app",
            "Maps.app", "Messages.app", "FaceTime.app", "Contacts.app", "Calendar.app",
            "Reminders.app", "Notes.app", "Freeform.app", "Clock.app", "Weather.app",
            "Stocks.app", "VoiceMemos.app", "Home.app", "FindMy.app", "Shortcuts.app",
            "Preview.app", "QuickTime Player.app", "TextEdit.app", "Calculator.app",
            "Chess.app", "Dictionary.app", "Image Capture.app", "Photo Booth.app",
            "Stickies.app", "System Settings.app", "System Preferences.app",
            "App Store.app", "Books.app", "Font Book.app", "Time Machine.app",
            "Mission Control.app", "Launchpad.app", "Automator.app", "Script Editor.app",
            "Terminal.app", "Activity Monitor.app", "Console.app", "Disk Utility.app",
            "Migration Assistant.app", "AirPort Utility.app", "Audio MIDI Setup.app",
            "Bluetooth File Exchange.app", "Boot Camp Assistant.app", "ColorSync Utility.app",
            "Digital Color Meter.app", "Grapher.app", "Keychain Access.app",
            "Screen Sharing.app", "Screenshot.app", "VoiceOver Utility.app",
            "Wireless Diagnostics.app", "Print Center.app", "iPhone Mirroring.app"
        ]
        let last = (path as NSString).lastPathComponent
        if appleNames.contains(last) { return true }

        return false
    }

    private func directorySize(_ path: String) -> Int64 {
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

    private func moveReplacing(from: String, to: String) throws {
        let fm = FileManager.default
        let fromURL = URL(fileURLWithPath: from)
        let toURL = URL(fileURLWithPath: to)
        if fm.fileExists(atPath: to) { try fm.removeItem(at: toURL) }
        try fm.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: fromURL, to: toURL)
        } catch {
            try fm.copyItem(at: fromURL, to: toURL)
            try fm.removeItem(at: fromURL)
        }
    }
}
