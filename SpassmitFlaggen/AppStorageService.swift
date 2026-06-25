import SwiftUI
import Foundation

enum AppStorageService {
    static let key = "flagTrainerAppDataV2"
    static let legacyStatsKey = "flagQuizStatsV1"

    static func load() -> AppData {
        guard let data = UserDefaults.standard.data(forKey: key),
              let appData = try? JSONDecoder().decode(AppData.self, from: data) else {
            return AppData()
        }

        return appData
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
}
