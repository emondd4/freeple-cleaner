import Foundation

struct DiskVolume: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let totalBytes: Int64
    let freeBytes: Int64
    let isInternal: Bool
    let isEjectable: Bool
    let isRemovable: Bool

    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes)
    }

    var isPortableCandidate: Bool {
        !isInternal && (isEjectable || isRemovable || path.hasPrefix("/Volumes/"))
    }

    var capacityLabel: String {
        "\(ByteCount.string(freeBytes)) free of \(ByteCount.string(totalBytes))"
    }
}
