import Foundation

enum AppStorageService {
    static let key = "flagTrainerAppDataV2"
    static let legacyStatsKey = "flagQuizStatsV1"

    private static let corruptBackupKeyPrefix = "flagTrainerAppDataV2DecodeBackup"
    private static let fileName = "flagTrainerAppDataV2.json"
    private static let writeQueue = DispatchQueue(
        label: "de.phil.Flaggenbande.AppDataWriter",
        qos: .utility
    )

    static func migrateLargeDefaultsToFilesIfNeeded() {
        migrateAppDataFromDefaultsIfNeeded()
        migrateCorruptDefaultsBackups()
        MiniLocationSnapshotStore.migrateLegacyIfNeeded()
        DailyCompletionQueue.migrateLegacyIfNeeded()
    }

    static func load() -> AppData {
        if let fileData = DataFileStore.read(fileName: fileName) {
            if let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) {
                removeLegacyAppDataDefault()
                return decoded
            }

            preserveUndecodableData(fileData)
            DataFileStore.remove(fileName: fileName)
        }

        guard let defaultsData = UserDefaults.standard.data(forKey: key) else {
            return AppData()
        }

        guard let decoded = try? JSONDecoder().decode(AppData.self, from: defaultsData) else {
            preserveUndecodableData(defaultsData)
            LegacyDefaultsMigration.removeData(forKey: key, migratedData: defaultsData)
            return AppData()
        }

        if DataFileStore.write(defaultsData, fileName: fileName) {
            LegacyDefaultsMigration.removeData(forKey: key, migratedData: defaultsData)
        }
        return decoded
    }

    /// Serializes encoding and atomic disk writes away from the UI thread.
    /// Callers coalesce frequent state changes before invoking this.
    static func save(_ data: AppData) {
        writeQueue.async {
            guard let encoded = try? JSONEncoder().encode(data) else { return }
            _ = DataFileStore.write(encoded, fileName: fileName)
        }
    }

    /// Used when the app enters the background so the latest state is durable
    /// before iOS suspends the process.
    static func saveSynchronously(_ data: AppData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        writeQueue.sync {
            _ = DataFileStore.write(encoded, fileName: fileName)
        }
        removeLegacyAppDataDefault()
    }

    static func reset() {
        writeQueue.sync {
            DataFileStore.remove(fileName: fileName)
        }
        LegacyDefaultsMigration.removeData(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyStatsKey)
    }

    static func removeLegacyLocalPremiumFlagIfNeeded() {
        guard UserDefaults.standard.object(forKey: "fullVersionUnlocked") != nil else { return }
        UserDefaults.standard.removeObject(forKey: "fullVersionUnlocked")
        #if DEBUG
        print("[StoreKitManager] Removed legacy local premium cache key fullVersionUnlocked.")
        #endif
    }

    private static func migrateAppDataFromDefaultsIfNeeded() {
        guard let defaultsData = UserDefaults.standard.data(forKey: key) else { return }

        if let fileData = DataFileStore.read(fileName: fileName),
           (try? JSONDecoder().decode(AppData.self, from: fileData)) != nil {
            LegacyDefaultsMigration.removeData(forKey: key, migratedData: defaultsData)
            return
        }

        guard (try? JSONDecoder().decode(AppData.self, from: defaultsData)) != nil else {
            preserveUndecodableData(defaultsData)
            LegacyDefaultsMigration.removeData(forKey: key, migratedData: defaultsData)
            return
        }

        // Remove the old preference only after the atomic file write succeeds.
        if DataFileStore.write(defaultsData, fileName: fileName) {
            LegacyDefaultsMigration.removeData(forKey: key, migratedData: defaultsData)
        }
    }

    private static func migrateCorruptDefaultsBackups() {
        for legacyKey in UserDefaults.standard.dictionaryRepresentation().keys
        where legacyKey.hasPrefix(corruptBackupKeyPrefix) {
            guard let data = UserDefaults.standard.data(forKey: legacyKey) else { continue }
            if DataFileStore.write(data, fileName: "CorruptBackups/\(legacyKey).json") {
                LegacyDefaultsMigration.removeData(forKey: legacyKey, migratedData: data)
            }
        }
    }

    private static func preserveUndecodableData(_ data: Data) {
        let name = "CorruptBackups/\(corruptBackupKeyPrefix)-\(Int(Date().timeIntervalSince1970)).json"
        _ = DataFileStore.write(data, fileName: name)
    }

    private static func removeLegacyAppDataDefault() {
        guard UserDefaults.standard.object(forKey: key) != nil else { return }
        LegacyDefaultsMigration.removeData(forKey: key)
    }
}

/// Removing an already oversized value through `removeObject` can make
/// CFPreferences try to serialize the still-unmodified domain once more. For
/// those legacy edge cases, replace the persistent domain with a copy that no
/// longer contains the migrated value. Other settings, including StoreKit's
/// local purchase cache, remain untouched.
enum LegacyDefaultsMigration {
    private static let directDomainRewriteThreshold = 3_000_000

    static func removeData(forKey key: String, migratedData: Data? = nil) {
        let defaults = UserDefaults.standard
        let dataSize = migratedData?.count ?? defaults.data(forKey: key)?.count ?? 0

        guard dataSize >= directDomainRewriteThreshold,
              let domainName = Bundle.main.bundleIdentifier,
              var domain = defaults.persistentDomain(forName: domainName) else {
            defaults.removeObject(forKey: key)
            return
        }

        domain.removeValue(forKey: key)
        defaults.setPersistentDomain(domain, forName: domainName)
    }
}

enum DataFileStore {
    private static let directoryName = "StoredData"

    static func read(fileName: String) -> Data? {
        try? Data(contentsOf: fileURL(fileName: fileName), options: [.mappedIfSafe])
    }

    @discardableResult
    static func write(_ data: Data, fileName: String) -> Bool {
        do {
            let url = fileURL(fileName: fileName)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            #if DEBUG
            print("[DataFileStore] Could not write \(fileName): \(error)")
            #endif
            return false
        }
    }

    static func remove(fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(fileName: fileName))
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(fileName: fileName).path)
    }

    private static func fileURL(fileName: String) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "SpassmitFlaggen", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
