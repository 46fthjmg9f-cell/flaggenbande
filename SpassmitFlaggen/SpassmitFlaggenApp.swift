//
//  SpassmitFlaggenApp.swift
//  SpassmitFlaggen
//
//  Created by Philipp Rämer on 03.06.26.
//

import SwiftUI

@main
struct SpassmitFlaggenApp: App {
    init() {
        AppStorageService.migrateLargeDefaultsToFilesIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
