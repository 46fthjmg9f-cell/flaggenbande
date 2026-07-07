import SwiftUI
import Foundation

enum AppStorageService {
    static let key = "flagTrainerAppDataV2"
    static let legacyStatsKey = "flagQuizStatsV1"
    private static let corruptBackupKeyPrefix = "flagTrainerAppDataV2DecodeBackup"

    static func load() -> AppData {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return AppData()
        }

        do {
            return try JSONDecoder().decode(AppData.self, from: data)
        } catch {
            preserveUndecodableData(data)
            return AppData()
        }
    }

    static func save(_ data: AppData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyStatsKey)
    }

    static func removeLegacyLocalPremiumFlagIfNeeded() {
        guard UserDefaults.standard.object(forKey: "fullVersionUnlocked") != nil else { return }
        UserDefaults.standard.removeObject(forKey: "fullVersionUnlocked")
        #if DEBUG
        print("[StoreKitManager] Removed legacy local premium cache key fullVersionUnlocked.")
        #endif
    }

    private static func preserveUndecodableData(_ data: Data) {
        let backupKey = "\(corruptBackupKeyPrefix)-\(Int(Date().timeIntervalSince1970))"
        UserDefaults.standard.set(data, forKey: backupKey)
    }
}
