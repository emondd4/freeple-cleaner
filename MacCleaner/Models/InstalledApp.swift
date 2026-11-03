import Foundation
import AppKit

struct InstalledApp: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String?
    let byteSize: Int64
    let isAppleOrSystem: Bool
    var isRemapped: Bool
    var selected: Bool

    var sizeLabel: String { ByteCount.string(byteSize) }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

struct AppRemapRecord: Identifiable, Codable, Equatable {
    var id: String
    var appName: String
    var bundleIdentifier: String?
    var originalPath: String
    var destinationPath: String
    var volumePath: String
    var volumeName: String
    var createdAt: Date
    var bytesMoved: Int64

    var isVolumeMounted: Bool {
        FileManager.default.fileExists(atPath: volumePath)
    }
}

struct AppRemapStore: Codable {
    var records: [AppRemapRecord]

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-remaps.json")
    }

    static func load() -> AppRemapStore {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(AppRemapStore.self, from: data) else {
            return AppRemapStore(records: [])
        }
        return store
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL, options: .atomic)
    }
}
