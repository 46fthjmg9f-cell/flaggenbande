import SwiftUI
import StoreKit

// MARK: - Start And Menu Views

extension ContentView {
    var startView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()

            fixedMenuLayout(maxWidth: 520) {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 76, weight: .regular))
                            .foregroundStyle(tealAccentColor.opacity(0.42))
                            .padding(.bottom, 2)

                        HStack(spacing: 8) {
                            Text("Flaggenbande")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            if tierDecayPopup != nil {
                                Button {
                                    Haptics.tap()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        tierDecayInfoPopup = tierDecayPopup
                                        tierDecayInfoIsExpanded = true
                                        tierDecayPopup = nil
                                        selectedTierDecayChangeID = nil
                                        tierDecayShowsAllChanges = false
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .stroke(Color.red.opacity(tierDecayInfoPulse ? 0.08 : 0.42), lineWidth: 2)
                                            .frame(width: 36, height: 36)
                                            .scaleEffect(tierDecayInfoPulse ? 1.55 : 0.8)
                                        Circle()
                                            .fill(Color.red.opacity(0.14))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "info.circle.fill")
                                            .font(.title2.weight(.black))
                                            .foregroundStyle(.red)
                                            .scaleEffect(tierDecayInfoPulse ? 1.22 : 0.9)
                                            .rotationEffect(.degrees(tierDecayInfoWiggle ? 8 : -8))
                                    }
                                    .frame(width: 38, height: 38)
                                    .animation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true), value: tierDecayInfoPulse)
                                    .animation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true), value: tierDecayInfoWiggle)
                                    .accessibilityLabel(L("Stufeninfo", "Level info"))
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    tierDecayInfoPulse = true
                                    tierDecayInfoWiggle = true
                                }
                            }
                        }


                        Label(L("Streak: \(currentLearningStreak) Tage", "Streak: \(currentLearningStreak) days"), systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(currentLearningStreak > 0 ? .orange : .secondary)
                    }

                    subjectModePickerCard()

                    VStack(spacing: 12) {
                        ForEach(mainMenuScreens, id: \.self) { screen in
                            menuScreenRow(screen)
                        }
                    }

                    Button {
                        Haptics.tap()
                        guard !fullVersionUnlocked else { return }
                        isShowingFullVersionSheet = true
                    } label: {
                        Label(
                            fullVersionUnlocked ? L("Vollversion freigeschaltet", "Full version unlocked") : L("Vollversion freischalten", "Unlock full version"),
                            systemImage: fullVersionUnlocked ? "checkmark.seal.fill" : "lock.open.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fullVersionUnlocked ? tealAccentColor : .pink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(panelBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(storeKit.isPurchasing)
                    .buttonStyle(.plain)
                }
            }

            if let leagueSummaryResult {
                leagueSummaryOverlay(leagueSummaryResult)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.24).ignoresSafeArea())
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(3)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    var fullVersionUpsellSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(tealAccentColor)
                            .frame(width: 72, height: 72)
                            .background(tealAccentColor.opacity(0.14), in: Circle())

                        Text(L("Schalte die ganze Flaggenbande frei", "Unlock all of Flaggenbande"))
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(L("Kostenlos lernst du Flaggen und Hauptstädte mit Tageslimits. Mit der Vollversion wird daraus dein unbegrenzter Welttrainer - mit Globus, mehr Auswertung und ohne tägliche Rundenbegrenzung.", "The free version lets you learn flags and capitals with daily limits. The full version turns it into your unlimited world trainer with the globe, deeper stats, and no daily round caps."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        fullVersionFeatureRow(icon: "infinity", title: L("Keine Tageslimits", "No daily limits"), text: L("Trainiere Karten, Flaggenrun und Partymodus so oft, wie du möchtest.", "Train cards, Flag Run, and Party Mode as often as you want."))
                        fullVersionFeatureRow(icon: "globe", title: L("Interaktiver Globus", "Interactive globe"), text: L("Sieh deinen Fortschritt direkt auf der Weltkarte und springe gezielt zu Ländern, die noch offen sind.", "See your progress directly on the world map and jump to countries that still need work."))
                        fullVersionFeatureRow(icon: "chart.line.uptrend.xyaxis", title: L("Premium-Statistiken", "Premium statistics"), text: L("Verfolge Stufen, Lernkurven, Tagesleistung und Fortschritt pro Region viel genauer.", "Track levels, learning curves, daily performance, and regional progress in much more detail."))
                        fullVersionFeatureRow(icon: "paintpalette.fill", title: L("Mehr Anpassung", "More customization"), text: L("Schalte Akzentfarben und erweiterte Lernbereiche frei, damit sich die App nach deinem Trainer anfühlt.", "Unlock accent colors and expanded study scopes so the app feels like your own trainer."))
                        fullVersionFeatureRow(icon: "hand.raised.fill", title: L("Werbefrei. Immer.", "Ad-free. Always."), text: L("Niemand mag Werbung beim Lernen. Deshalb zeigt Flaggenbande bewusst weder in der kostenlosen Version noch in der Vollversion jemals Werbung.", "Nobody likes ads while learning. That's why Flaggenbande intentionally never shows ads, neither in the free version nor in the full version."))
                    }

                    Button(L("Später", "Later")) {
                        Haptics.tap()
                        isShowingFullVersionSheet = false
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                }
                .padding(18)
            }
            .background(appBackgroundGradient.ignoresSafeArea())
            .navigationTitle(L("Vollversion", "Full version"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Schließen", "Close")) {
                        isShowingFullVersionSheet = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                fullVersionPurchaseButton
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
            }
            .task {
                if storeKit.fullVersionProduct == nil {
                    await storeKit.loadProducts(reportErrors: true, refreshPurchasedEntitlements: false)
                }
            }
        }
    }

    var fullVersionPurchaseTitle: String {
        if let product = storeKit.fullVersionProduct {
            return L("Jetzt für \(product.displayPrice) freischalten", "Unlock now for \(product.displayPrice)")
        }
        return L("Vollversion kaufen", "Buy full version")
    }

    var fullVersionPurchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.tap()
                Task {
                    let purchaseSucceeded = await storeKit.purchaseFullVersion()
                    fullVersionUnlocked = storeKit.purchasedFullVersion
                    if purchaseSucceeded && fullVersionUnlocked {
                        isShowingFullVersionSheet = false
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if storeKit.isPurchasing || storeKit.isLoading || storeKit.isRefreshingEntitlements {
                        ProgressView()
                    } else {
                        Image(systemName: "lock.open.fill")
                    }
                    Text(storeKit.isLoading ? L("Store lädt ...", "Loading store ...") : fullVersionPurchaseTitle)
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
            .disabled(storeKit.isPurchasing || storeKit.isLoading || storeKit.isRefreshingEntitlements || fullVersionUnlocked)

            if let statusText = storeKit.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func fullVersionFeatureRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(tealAccentColor)
                .frame(width: 34, height: 34)
                .background(tealAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    func fixedMenuLayout<Content: View>(maxWidth: CGFloat, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            let baseHeight: CGFloat = maxWidth <= 520 ? 650 : 430
            let availableHeight = max(geometry.size.height - 28, 1)
            let scale = min(1, availableHeight / baseHeight)

            content()
                .padding()
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .scaleEffect(scale, anchor: .top)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .allowsHitTesting(true)
        }
    }

    var mainMenuScreens: [AppScreen] {
        [.games, .statistics, .globe, .achievements, .friends, .options]
    }

    var gameModeScreens: [AppScreen] {
        [.practice, .showmaster, .miniWorldCup, .league]
    }

    func menuScreenRow(_ screen: AppScreen) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: screen) {
                HStack(spacing: 14) {
                    Image(systemName: screen.iconName)
                        .font(.title3)
                        .frame(width: 28)
                    Text(screenTitle(screen))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer()
                    if screen == .globe && !fullVersionUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .contentShape(Rectangle())
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                selectedMenuInfoScreen = screen
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tealAccentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Info zu \(screenTitle(screen))", "Info about \(screenTitle(screen))"))
        }
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var gameModesView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            fixedMenuLayout(maxWidth: 620) {
                VStack(spacing: 18) {
                    modeHeader(title: L("Spielen", "Play"), subtitle: L("Wähle einen Spielmodus.", "Choose a game mode."))
                    subjectModePickerCard()
                    VStack(spacing: 12) {
                        ForEach(gameModeScreens, id: \.self) { screen in
                            menuScreenRow(screen)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Spielen", "Play"))
        .navigationBarTitleDisplayMode(.inline)
    }

    func menuInfoSheet(for screen: AppScreen) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: screen.iconName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(tealAccentColor)
                        .frame(width: 54, height: 54)
                        .background(tealAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    Text(screenTitle(screen))
                        .font(.headline.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(screenInfoText(screen))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundGradient.ignoresSafeArea())
            .navigationTitle(L("Info", "Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        selectedMenuInfoScreen = nil
                    }
                }
            }
        }
        .presentationDetents([.height(310), .medium])
    }
}
