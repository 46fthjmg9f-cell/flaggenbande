import SwiftUI
import Foundation
import StoreKit

extension ContentView {
    var optionsView: some View {
        List {
            Section(L("Vollversion", "Full version")) {
                if fullVersionUnlocked {
                    Label(L("Du hast die Vollversion, Dankeschön!", "You have the full version, thank you!"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(tealAccentColor)
                } else {
                    Button {
                        Haptics.tap()
                        Task {
                            await storeKit.purchaseFullVersion()
                            fullVersionUnlocked = storeKit.purchasedFullVersion
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Label(L("Vollversion kaufen", "Buy full version"), systemImage: "lock.open.fill")
                            Spacer()
                            if storeKit.isPurchasing {
                                ProgressView()
                            } else if let product = storeKit.fullVersionProduct {
                                Text(product.displayPrice)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tealAccentColor)
                            } else {
                                Text(L("Preis lädt", "Loading price"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(storeKit.isPurchasing)
                }

                if !fullVersionUnlocked {
                    Button {
                        Haptics.tap()
                        Task {
                            await storeKit.restorePurchases()
                            fullVersionUnlocked = storeKit.purchasedFullVersion
                        }
                    } label: {
                        Label(L("Käufe wiederherstellen", "Restore purchases"), systemImage: "arrow.clockwise")
                    }
                    .disabled(storeKit.isLoading)
                }
            }

            Section(L("Sprache", "Language")) {
                Picker(L("Sprache", "Language"), selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L("Theme", "Theme")) {
                Picker(L("Theme", "Theme"), selection: $appThemeRawValue) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(language: appLanguage)).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L("Akzentfarbe", "Accent color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                    ForEach(AppAccent.allCases) { accent in
                        accentColorButton(for: accent)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L("Flaggen", "Flags")) {
                HStack(spacing: 10) {
                    Toggle(isOn: $includePartiallyRecognizedFlags) {
                        Label(L("Teilweise anerkannte Gebiete", "Partly recognized territories"), systemImage: "checkmark.seal")
                    }

                    infoButton(isPresented: $isDisputedTerritoriesInfoExpanded) {
                        Text(L("Fügt unter anderem Kosovo, Taiwan, Palästina, Westsahara, Cookinseln, Niue, Abchasien, Südossetien, Nordzypern und Somaliland hinzu. Diese Auswahl ist als Lern-Erweiterung gemeint und trifft keine politische Einordnung.", "Adds Kosovo, Taiwan, Palestine, Western Sahara, Cook Islands, Niue, Abkhazia, South Ossetia, Northern Cyprus, and Somaliland. This option is intended as a learning extension and does not make a political classification."))
                    }
                }
            }

            Section(L("Bedienung", "Controls")) {
                Toggle(isOn: $hapticsEnabled) {
                    Label(L("Vibration", "Haptics"), systemImage: "iphone.radiowaves.left.and.right")
                }
            }

            Section(L("Online", "Online")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(L("Spitzname", "Nickname"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        infoButton(isPresented: $isShowingNicknameInfo) {
                            Text(L("Optional und eindeutig. Freunde können dich darunter finden. Ohne Spitznamen wird dein Game-Center-Name angezeigt.", "Optional and unique. Friends can find you by it. Without a nickname, your Game Center name is shown."))
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "at")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tealAccentColor)
                            .frame(width: 24)
                        TextField(L("anzeigename", "display name"), text: $onlinePlayerName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tealAccentColor.opacity(0.24), lineWidth: 1)
                    )
                }
            }

            Section(L("Spenden", "Tips")) {
                if storeKit.donationProducts.isEmpty {
                    Label(L("Spenden laden", "Loading tips"), systemImage: "heart")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(storeKit.donationProducts, id: \.id) { product in
                        Button {
                            Haptics.tap()
                            Task {
                                await storeKit.purchase(product)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Label(product.displayName, systemImage: "heart.fill")
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.pink)
                            }
                        }
                        .disabled(storeKit.isLoading)
                    }
                }
            }

            if let statusText = storeKit.statusText {
                Section {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            #if DEBUG
            Section("Debug") {
                Toggle(isOn: $debugToolsEnabled) {
                    Label(L("Debug-Werkzeuge", "Debug tools"), systemImage: "ladybug.fill")
                }

                if debugToolsEnabled {
                    Toggle(isOn: $fullVersionUnlocked) {
                        Label(L("Vollversion freischalten", "Unlock full version"), systemImage: "lock.open.fill")
                    }

                    Stepper(value: Binding(
                        get: { activeProfile.leagueStats?.bestScore ?? 0 },
                        set: { debugSetFlaggenrunHighscore($0) }
                    ), in: 0...100000, step: 500) {
                        Label("\(runHighscoreTitle): \(activeProfile.leagueStats?.bestScore ?? 0)", systemImage: "chart.line.uptrend.xyaxis")
                    }

                    Button {
                        Haptics.tap()
                        debugResetLeagueStats()
                    } label: {
                        Label(L("\(runTitle)-Stats zurücksetzen", "Reset \(runTitle) stats"), systemImage: "arrow.counterclockwise")
                    }

                    Menu {
                        ForEach(MasteryTier.allCases) { tier in
                            Button(tier.rawValue) {
                                Haptics.tap()
                                debugSetAllCountryTiers(tier)
                            }
                        }
                    } label: {
                        Label(L("Alle Flaggen-Stufen setzen", "Set all flag tiers"), systemImage: "slider.horizontal.3")
                    }

                    Button {
                        Haptics.tap()
                        Task { await createTestFriend() }
                    } label: {
                        Label(L("Testfreund erstellen/aktualisieren", "Create/update test friend"), systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(isSyncingOnlineStats)

                    Text(L("Diese Werkzeuge sind nur in Debug-Builds sichtbar und werden im Release nicht kompiliert.", "These tools are only visible in Debug builds and are not compiled into Release."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #endif

            Section(L("Daten", "Data")) {
                Button(role: .destructive) {
                    Haptics.tap()
                    isShowingResetConfirmation = true
                } label: {
                    Text(L("Alle lokalen Daten zurücksetzen", "Reset all local data"))
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Optionen", "Options"))
        .alert(L("Store", "Store"), isPresented: Binding(
            get: { storeKit.statusText != nil },
            set: { isPresented in
                if !isPresented {
                    storeKit.statusText = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                storeKit.statusText = nil
            }
        } message: {
            Text(storeKit.statusText ?? "")
        }
        .task {
            guard !fullVersionUnlocked else { return }
            await storeKit.loadProducts()
            fullVersionUnlocked = storeKit.purchasedFullVersion
        }
    }


}
