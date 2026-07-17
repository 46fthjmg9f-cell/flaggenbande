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
                        isShowingFullVersionSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Label(L("Vollversion kaufen", "Buy full version"), systemImage: "lock.open.fill")
                            Spacer()
                            if storeKit.isPurchasing || storeKit.isLoading || storeKit.isRefreshingEntitlements {
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
                    .disabled(storeKit.isPurchasing || storeKit.isLoading || storeKit.isRefreshingEntitlements)
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
                    .disabled(storeKit.isLoading || storeKit.isPurchasing || storeKit.isRefreshingEntitlements)
                }
            }

            Section(L("Sprache", "Language")) {
                Picker(L("Sprache", "Language"), selection: Binding(
                    get: { appLanguage },
                    set: { language in
                        Haptics.tap()
                        appLanguageRawValue = language.rawValue
                    }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
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
                territoryOptionRow(
                    title: L("Teilweise anerkannte Gebiete", "Partly recognized territories"),
                    systemImage: "checkmark.seal",
                    isExpanded: Binding(
                        get: { isDisputedTerritoriesInfoExpanded },
                        set: { isExpanded in
                            isDisputedTerritoriesInfoExpanded = isExpanded
                            if isExpanded { isDependentTerritoriesInfoExpanded = false }
                        }
                    ),
                    isEnabled: Binding(
                        get: { includePartiallyRecognizedFlags },
                        set: { isEnabled in
                            includePartiallyRecognizedFlags = isEnabled
                            excludedPartiallyRecognizedCountryCodesRawValue = isEnabled ? "" : partiallyRecognizedCountries.map(\.code).sorted().joined(separator: ",")
                            resetCountryPoolDependentState()
                        }
                    )
                )

                if isDisputedTerritoriesInfoExpanded {
                    territorySelectionPanel(
                        text: L("Diese Auswahl ist als Lern-Erweiterung gemeint und trifft keine politische Einordnung.", "This option is intended as a learning extension and does not make a political classification."),
                        countries: partiallyRecognizedCountries,
                        excludedCodes: excludedPartiallyRecognizedCountryCodes,
                        rawValue: $excludedPartiallyRecognizedCountryCodesRawValue,
                        isGroupEnabled: $includePartiallyRecognizedFlags
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                territoryOptionRow(
                    title: L("Abhängige Länder und Gebiete", "Dependent countries and territories"),
                    systemImage: "flag.2.crossed.fill",
                    isExpanded: Binding(
                        get: { isDependentTerritoriesInfoExpanded },
                        set: { isExpanded in
                            isDependentTerritoriesInfoExpanded = isExpanded
                            if isExpanded { isDisputedTerritoriesInfoExpanded = false }
                        }
                    ),
                    isEnabled: Binding(
                        get: { includeDependentTerritories },
                        set: { isEnabled in
                            includeDependentTerritories = isEnabled
                            excludedDependentTerritoryCodesRawValue = isEnabled ? "" : dependentTerritoryCountries.map(\.code).sorted().joined(separator: ",")
                            resetCountryPoolDependentState()
                        }
                    )
                )

                if isDependentTerritoriesInfoExpanded {
                    territorySelectionPanel(
                        text: L("Diese Auswahl zeigt zusätzliche Länder, Landesteile und abhängige Gebiete nur als Lern-Erweiterung und ist keine politische Einordnung.", "This option shows additional countries, constituent countries, and dependent territories only as a learning extension and does not make a political classification."),
                        countries: dependentTerritoryCountries,
                        excludedCodes: excludedDependentTerritoryCodes,
                        rawValue: $excludedDependentTerritoryCodesRawValue,
                        isGroupEnabled: $includeDependentTerritories
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Section(L("Bedienung", "Controls")) {
                Toggle(isOn: $hapticsEnabled) {
                    Label(L("Vibration", "Haptics"), systemImage: "iphone.radiowaves.left.and.right")
                }
            }

            Section(L("Online", "Online")) {
                Toggle(isOn: $onlineFeaturesEnabled) {
                    Label(L("Onlinefunktionen", "Online features"), systemImage: "icloud")
                }

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
                    Button(role: .destructive) {
                        Haptics.notify(.warning)
                        storeKit.resetLocalPremiumStatusForDebug()
                        fullVersionUnlocked = false
                    } label: {
                        Label(L("Lokalen Premiumstatus zurücksetzen", "Reset local premium status"), systemImage: "lock.slash.fill")
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
        .background(
            appBackgroundGradient
                .ignoresSafeArea()
                .onTapGesture {
                    collapseTerritoryPanels()
                }
        )
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
            await storeKit.loadProducts()
            fullVersionUnlocked = storeKit.purchasedFullVersion
        }
    }

    func territoryOptionRow(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        isEnabled: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tealAccentColor)
                        .frame(width: 22)

                    Text(title)
                        .font(.body)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "info.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tealAccentColor)

                    Spacer(minLength: 4)

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func territorySelectionPanel(
        text: String,
        countries: [Country],
        excludedCodes: Set<String>,
        rawValue: Binding<String>,
        isGroupEnabled: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(countries) { country in
                        territorySelectionRow(
                            country: country,
                            excludedCodes: excludedCodes,
                            rawValue: rawValue,
                            isGroupEnabled: isGroupEnabled
                        )
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: 260)

            Divider()

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tealAccentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.2), lineWidth: 1)
        )
    }

    func territorySelectionRow(
        country: Country,
        excludedCodes: Set<String>,
        rawValue: Binding<String>,
        isGroupEnabled: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Text(countryName(for: country))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { isGroupEnabled.wrappedValue && !excludedCodes.contains(country.code) },
                set: { isIncluded in
                    Haptics.tap()
                    if isIncluded {
                        isGroupEnabled.wrappedValue = true
                    }
                    setExcludedCode(country.code, isExcluded: !isIncluded, rawValue: rawValue)
                    resetCountryPoolDependentState()
                }
            ))
            .labelsHidden()
            .fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
    }

    func collapseTerritoryPanels() {
        guard isDisputedTerritoriesInfoExpanded || isDependentTerritoriesInfoExpanded else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            isDisputedTerritoriesInfoExpanded = false
            isDependentTerritoriesInfoExpanded = false
        }
    }
}
