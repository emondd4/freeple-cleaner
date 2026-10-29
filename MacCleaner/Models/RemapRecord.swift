import Foundation

enum RemapMode: String, Codable {
    case wholeFolder
    case children
}

struct RemapRecord: Identifiable, Codable, Equatable {
    var id: String
    var categoryRaw: String
    var originalPath: String
    var destinationPath: String
    var volumePath: String
    var volumeName: String
    var createdAt: Date
    var bytesMoved: Int64
    var mode: RemapMode

    enum CodingKeys: String, CodingKey {
        case id, categoryRaw, originalPath, destinationPath
        case volumePath, volumeName, createdAt, bytesMoved, mode
    }

    init(
        id: String,
        categoryRaw: String,
        originalPath: String,
        destinationPath: String,
        volumePath: String,
        volumeName: String,
        createdAt: Date,
        bytesMoved: Int64,
        mode: RemapMode = .wholeFolder
    ) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.originalPath = originalPath
        self.destinationPath = destinationPath
        self.volumePath = volumePath
        self.volumeName = volumeName
        self.createdAt = createdAt
        self.bytesMoved = bytesMoved
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        categoryRaw = try c.decode(String.self, forKey: .categoryRaw)
        originalPath = try c.decode(String.self, forKey: .originalPath)
        destinationPath = try c.decode(String.self, forKey: .destinationPath)
        volumePath = try c.decode(String.self, forKey: .volumePath)
        volumeName = try c.decode(String.self, forKey: .volumeName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        bytesMoved = try c.decode(Int64.self, forKey: .bytesMoved)
        mode = try c.decodeIfPresent(RemapMode.self, forKey: .mode) ?? .wholeFolder
    }

    var category: CategoryKind? {
        CategoryKind(rawValue: categoryRaw)
    }

    var isLinkIntact: Bool {
        if mode == .children {
            return isDestinationPresent
        }
        return PathSafety.isSymlink(originalPath)
    }

    var isVolumeMounted: Bool {
        FileManager.default.fileExists(atPath: volumePath)
    }

    var isDestinationPresent: Bool {
        FileManager.default.fileExists(atPath: destinationPath)
    }
}

struct RemapStore: Codable {
    var records: [RemapRecord]

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("remaps.json")
    }

    static func load() -> RemapStore {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(RemapStore.self, from: data) else {
            return RemapStore(records: [])
        }
        return store
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL, options: .atomic)
    }
}
