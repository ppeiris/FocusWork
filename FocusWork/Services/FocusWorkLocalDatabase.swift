import Foundation

// MARK: - Application Support layout (per bundle identifier)

/// Resolves `~/Library/Application Support/<bundle-id>/…` so Debug, Release, and differently signed builds keep separate data (standard macOS practice).
enum AppSupportLayout {
    /// e.g. `…/Application Support/com.focuswork.FocusWork` or `…com.focuswork.FocusWork.debug`
    static var applicationSupportBundleContainer: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bundleId = Bundle.main.bundleIdentifier ?? "com.focuswork.FocusWork"
        return root.appendingPathComponent(bundleId, isDirectory: true)
    }

    /// App-owned subtree (documents, local DB, future caches).
    static var focusWorkApplicationDirectory: URL {
        applicationSupportBundleContainer.appendingPathComponent("FocusWork", isDirectory: true)
    }

    /// JSON “database” for vault bindings and paths shipped with / created by this install.
    static var localDatabaseFileURL: URL {
        focusWorkApplicationDirectory.appendingPathComponent("LocalDatabase.json", isDirectory: false)
    }
}

// MARK: - Persisted model (versioned for forward-compatible migrations)

/// One Obsidian vault the user linked to this install. Project markdown lives under `vaultRoot` + `projectsFolderRelativePath`.
struct VaultRecord: Codable, Equatable, Identifiable {
    var id: UUID
    /// Standardized absolute filesystem path to the vault folder (what you open in Obsidian).
    var vaultRootPath: String
    /// Relative path from vault root to the directory containing `project_*.md` (default matches vault spec).
    var projectsFolderRelativePath: String
    /// Optional label in UI later; vault folder name is a fine default.
    var displayTitle: String?

    init(
        id: UUID = UUID(),
        vaultRootPath: String,
        projectsFolderRelativePath: String = VaultRecord.defaultProjectsFolderRelativePath,
        displayTitle: String? = nil
    ) {
        self.id = id
        self.vaultRootPath = vaultRootPath
        self.projectsFolderRelativePath = projectsFolderRelativePath
        self.displayTitle = displayTitle
    }

    static let defaultProjectsFolderRelativePath = "FocusWork/Projects"
}

struct LocalDatabasePayload: Codable, Equatable {
    var schemaVersion: Int
    var vaults: [VaultRecord]
    var activeVaultId: UUID?

    static let currentSchemaVersion = 1

    init(schemaVersion: Int = LocalDatabasePayload.currentSchemaVersion, vaults: [VaultRecord] = [], activeVaultId: UUID? = nil) {
        self.schemaVersion = schemaVersion
        self.vaults = vaults
        self.activeVaultId = activeVaultId
    }
}

// MARK: - Atomic JSON persistence

/// Small on-disk store for vault location(s). Uses JSON in Application Support (common for lightweight Mac apps; SQLite can replace later if needed).
final class FocusWorkLocalDatabase {
    static let shared = FocusWorkLocalDatabase()

    /// Legacy `UserDefaults` key from before the local file existed.
    private let legacyUserDefaultsVaultPathKey = "focuswork.obsidian.vaultPath"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()
    private let ioLock = NSLock()

    private init() {}

    func loadPayload() -> LocalDatabasePayload {
        ioLock.lock()
        defer { ioLock.unlock() }

        if FileManager.default.fileExists(atPath: AppSupportLayout.localDatabaseFileURL.path) {
            do {
                let data = try Data(contentsOf: AppSupportLayout.localDatabaseFileURL)
                let decoded = try decoder.decode(LocalDatabasePayload.self, from: data)
                let migrated = migrateIfNeeded(decoded)
                if migrated != decoded {
                    try? savePayloadUnlocked(migrated)
                }
                return migrated
            } catch {
                return migrateUserDefaultsIntoFreshPayload()
            }
        }
        return migrateUserDefaultsIntoFreshPayload()
    }

    private func migrateIfNeeded(_ payload: LocalDatabasePayload) -> LocalDatabasePayload {
        var p = payload
        switch p.schemaVersion {
        case LocalDatabasePayload.currentSchemaVersion:
            break
        default:
            p.schemaVersion = LocalDatabasePayload.currentSchemaVersion
        }
        return p
    }

    private func migrateUserDefaultsIntoFreshPayload() -> LocalDatabasePayload {
        guard let path = UserDefaults.standard.string(forKey: legacyUserDefaultsVaultPathKey),
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LocalDatabasePayload()
        }
        let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        let record = VaultRecord(vaultRootPath: standardized)
        let payload = LocalDatabasePayload(vaults: [record], activeVaultId: record.id)
        try? savePayloadUnlocked(payload)
        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsVaultPathKey)
        return payload
    }

    func savePayload(_ payload: LocalDatabasePayload) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        try savePayloadUnlocked(payload)
    }

    private func savePayloadUnlocked(_ payload: LocalDatabasePayload) throws {
        let dir = AppSupportLayout.focusWorkApplicationDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(payload)
        let tmp = dir.appendingPathComponent("LocalDatabase.json.tmp", isDirectory: false)
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: AppSupportLayout.localDatabaseFileURL.path) {
            try FileManager.default.removeItem(at: AppSupportLayout.localDatabaseFileURL)
        }
        try FileManager.default.moveItem(at: tmp, to: AppSupportLayout.localDatabaseFileURL)
    }

    /// Current UX: a single linked vault. Clears all bindings when `root` is nil.
    func setLinkedVault(root: URL?, projectsFolderRelativePath: String = VaultRecord.defaultProjectsFolderRelativePath) throws {
        var payload = loadPayload()
        if let root {
            let path = root.standardizedFileURL.path
            let record = VaultRecord(vaultRootPath: path, projectsFolderRelativePath: projectsFolderRelativePath)
            payload.vaults = [record]
            payload.activeVaultId = record.id
        } else {
            payload.vaults = []
            payload.activeVaultId = nil
        }
        try savePayload(payload)
    }

    func activeVaultRecord() -> VaultRecord? {
        let payload = loadPayload()
        guard let id = payload.activeVaultId else { return nil }
        return payload.vaults.first { $0.id == id }
    }
}

extension URL {
    /// Appends path components from a relative string such as `FocusWork/Projects`.
    func appendingRelativeDirectoryPath(_ relative: String) -> URL {
        var base = self
        for part in relative.split(separator: "/") where !part.isEmpty {
            base = base.appendingPathComponent(String(part), isDirectory: true)
        }
        return base
    }
}
