import Foundation
import SwiftUI

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case userCaches
    case userLogs
    case temporaryFiles
    case xcodeDerivedData
    case xcodeArchives
    case iosDeviceSupport
    case coreSimulator
    case iosBackups
    case homebrewCache
    case npmCache
    case pipCache
    case cargoCache
    case trash
    case mailDownloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches: return "User Caches"
        case .userLogs: return "User Logs"
        case .temporaryFiles: return "Temporary Files"
        case .xcodeDerivedData: return "Xcode DerivedData"
        case .xcodeArchives: return "Xcode Archives"
        case .iosDeviceSupport: return "iOS Device Support"
        case .coreSimulator: return "Core Simulator"
        case .iosBackups: return "iOS Device Backups"
        case .homebrewCache: return "Homebrew Cache"
        case .npmCache: return "npm Cache"
        case .pipCache: return "pip Cache"
        case .cargoCache: return "Cargo Cache"
        case .trash: return "Trash"
        case .mailDownloads: return "Mail Downloads"
        }
    }

    var subtitle: String {
        switch self {
        case .userCaches: return "App caches in ~/Library/Caches"
        case .userLogs: return "Diagnostic logs in ~/Library/Logs"
        case .temporaryFiles: return "Files in /tmp and ~/Library/Caches/TemporaryItems"
        case .xcodeDerivedData: return "Build products and indexes"
        case .xcodeArchives: return "Archived .xcarchive builds"
        case .iosDeviceSupport: return "Device symbols for debugging"
        case .coreSimulator: return "iOS Simulator runtimes & data"
        case .iosBackups: return "Local iPhone/iPad backups"
        case .homebrewCache: return "Downloaded Homebrew bottles"
        case .npmCache: return "npm package cache"
        case .pipCache: return "Python pip download cache"
        case .cargoCache: return "Rust cargo registry cache"
        case .trash: return "Items in the user Trash"
        case .mailDownloads: return "Attachments saved by Mail"
        }
    }

    var systemImage: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .userLogs: return "doc.text"
        case .temporaryFiles: return "clock.arrow.circlepath"
        case .xcodeDerivedData: return "hammer"
        case .xcodeArchives: return "archivebox"
        case .iosDeviceSupport: return "iphone"
        case .coreSimulator: return "apps.iphone"
        case .iosBackups: return "externaldrive.badge.icloud"
        case .homebrewCache: return "mug"
        case .npmCache: return "shippingbox"
        case .pipCache: return "chevron.left.forwardslash.chevron.right"
        case .cargoCache: return "cube.box"
        case .trash: return "trash"
        case .mailDownloads: return "envelope"
        }
    }

    var accent: Color {
        switch self {
        case .userCaches, .temporaryFiles: return Color(red: 0.20, green: 0.55, blue: 0.72)
        case .userLogs, .mailDownloads: return Color(red: 0.45, green: 0.50, blue: 0.58)
        case .xcodeDerivedData, .xcodeArchives, .iosDeviceSupport, .coreSimulator:
            return Color(red: 0.18, green: 0.52, blue: 0.42)
        case .iosBackups: return Color(red: 0.25, green: 0.45, blue: 0.70)
        case .homebrewCache, .npmCache, .pipCache, .cargoCache:
            return Color(red: 0.55, green: 0.42, blue: 0.28)
        case .trash: return Color(red: 0.70, green: 0.35, blue: 0.30)
        }
    }

    /// Paths relative to home or absolute that make up this category.
    var paths: [String] {
        switch self {
        case .userCaches:
            return ["~/Library/Caches"]
        case .userLogs:
            return ["~/Library/Logs"]
        case .temporaryFiles:
            return [
                NSTemporaryDirectory(),
                "~/Library/Caches/TemporaryItems"
            ]
        case .xcodeDerivedData:
            return ["~/Library/Developer/Xcode/DerivedData"]
        case .xcodeArchives:
            return ["~/Library/Developer/Xcode/Archives"]
        case .iosDeviceSupport:
            return ["~/Library/Developer/Xcode/iOS DeviceSupport"]
        case .coreSimulator:
            return ["~/Library/Developer/CoreSimulator"]
        case .iosBackups:
            return ["~/Library/Application Support/MobileSync/Backup"]
        case .homebrewCache:
            return ["~/Library/Caches/Homebrew", "/opt/homebrew/var/cache"]
        case .npmCache:
            return ["~/.npm"]
        case .pipCache:
            return ["~/Library/Caches/pip"]
        case .cargoCache:
            return ["~/.cargo/registry/cache", "~/.cargo/registry/src"]
        case .trash:
            return ["~/.Trash"]
        case .mailDownloads:
            return ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]
        }
    }

    var canClean: Bool {
        switch self {
        case .iosBackups: return true // user must confirm; still allowed
        default: return true
        }
    }

    /// Categories safe/useful to relocate onto an external SSD via symlink.
    var canRemap: Bool {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .iosDeviceSupport,
             .coreSimulator, .iosBackups, .userCaches:
            return true
        default:
            return false
        }
    }

    /// ~/Library/Caches contains TCC-protected Apple folders; remap each child instead of the whole directory.
    var remapsChildrenIndependently: Bool {
        self == .userCaches
    }

    var riskNote: String? {
        switch self {
        case .iosBackups:
            return "Deletes local device backups. iCloud backups are unaffected."
        case .coreSimulator:
            return "Removes simulator devices and cached runtimes. They can be re-downloaded."
        case .iosDeviceSupport:
            return "Xcode will re-download symbols the next time you debug that iOS version."
        case .xcodeArchives:
            return "Deletes archived builds used for App Store / TestFlight uploads."
        case .userCaches:
            return "Apps may rebuild caches; some may feel slower until warmed up. Remap skips privacy-protected Apple folders unless Full Disk Access is granted."
        default:
            return nil
        }
    }
}
