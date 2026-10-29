import Foundation

struct CategoryScan: Identifiable, Equatable {
    let id: CategoryKind
    var kind: CategoryKind { id }
    var byteSize: Int64
    var itemCount: Int
    var exists: Bool
    var isRemapped: Bool
    var selected: Bool

    var sizeLabel: String {
        guard exists else { return "Not found" }
        return ByteCount.string(byteSize)
    }
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case clean
    case remap
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .clean: return "Clean"
        case .remap: return "Remap to SSD"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .clean: return "sparkles"
        case .remap: return "externaldrive.connected.to.line.below"
        case .settings: return "gearshape"
        }
    }
}
