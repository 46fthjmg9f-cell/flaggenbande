import SwiftUI

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

                        Text("Flaggenbande")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

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

                    NavigationLink(value: AppScreen.options) {
                        Label(
                            fullVersionUnlocked ? L("Du hast die Vollversion, Dankeschön!", "You have the full version, thank you!") : L("Vollversion freischalten", "Unlock full version"),
                            systemImage: fullVersionUnlocked ? "checkmark.seal.fill" : "lock.open.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fullVersionUnlocked ? tealAccentColor : .pink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(panelBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
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
