import SwiftUI

// MARK: - Beginner Mode

extension ContentView {
    var beginnerLimitReached: Bool {
        selectedBeginnerQuestionLimit > 0 && beginnerSessionResults.count >= selectedBeginnerQuestionLimit
    }

    var beginnerQuestionProgressText: String {
        let current = selectedBeginnerQuestionLimit > 0
            ? min(beginnerDisplayedQuestionNumber, selectedBeginnerQuestionLimit)
            : beginnerDisplayedQuestionNumber
        return selectedBeginnerQuestionLimit == 0
            ? L("\(current). Aufgabe · Endlos", "\(current). question · endless")
            : L("\(current) / \(selectedBeginnerQuestionLimit) Aufgaben", "\(current) / \(selectedBeginnerQuestionLimit) questions")
    }

    var beginnerStats: BeginnerStats {
        activeProfile.beginnerStats ?? BeginnerStats()
    }

    func beginnerLimitTitle(_ limit: Int) -> String {
        limit == 0 ? L("Endlos", "Endless") : L("\(limit) Aufgaben", "\(limit) questions")
    }

    var beginnerView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()

            adaptiveModeLayout {
                VStack(spacing: 18) {
                    modeHeader(title: L("Anfänger", "Beginner"), subtitle: "")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            recordBeginnerEasterEggTap()
                        }

                    if beginnerSessionActive {
                        Text(beginnerQuestionProgressText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        beginnerHistoryBar

                        beginnerQuestionCard

                        Button {
                            Haptics.tap()
                            isShowingBeginnerCancelConfirmation = true
                        } label: {
                            Text(L("Beenden", "End"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    } else {
                        beginnerSetupView
                    }
                }
            }

            if let beginnerHistoryPreview {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if practiceHistoryGlobeCountry != nil {
                            dismissPracticeHistoryGlobePreview()
                        } else {
                            dismissBeginnerHistoryPreview()
                        }
                    }
                    .zIndex(1)

                beginnerHistoryPopup(for: beginnerHistoryPreview)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 108)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(2)
            }

            if let practiceHistoryGlobeCountry, beginnerHistoryPreview != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissPracticeHistoryGlobePreview() }
                    .zIndex(3)

                practiceHistoryGlobePopup(for: practiceHistoryGlobeCountry)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(4)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: beginnerHistoryPreview?.id)
    }

    var beginnerSetupView: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Kategorie", "Category"))
                    .font(.headline)
                continentButtonGrid(selection: $selectedBeginnerContinents)
            }
            .padding(16)
            .appSurface()

            beginnerQuestionSettings

            if showBeginnerSummary {
                beginnerSummaryPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Spacer(minLength: 18)

            Button {
                Haptics.tap()
                startBeginnerSession()
            } label: {
                Text(L("Starten", "Start"))
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
    }

    var beginnerDirectionOptions: [BeginnerDirection] {
        selectedSubject == .capitals ? [.flagToCountry, .countryToFlag] : [.countryToFlag, .flagToCountry]
    }

    var beginnerQuestionSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Aufgaben", "Questions"))
                .font(.headline)

            Picker(L("Länge", "Length"), selection: Binding(
                get: { selectedBeginnerQuestionLimit == 0 ? 0 : 1 },
                set: { mode in
                    Haptics.tap()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        selectedBeginnerQuestionLimit = mode == 0 ? 0 : max(selectedBeginnerQuestionLimit, 10)
                    }
                }
            )) {
                Text(L("Endlos", "Endless")).tag(0)
                Text(L("Begrenzt", "Limited")).tag(1)
            }
            .pickerStyle(.segmented)

            Picker(L("Anzeige", "Shown item"), selection: $selectedBeginnerDirection) {
                ForEach(beginnerDirectionOptions) { direction in
                    Text(direction.title(language: appLanguage, subject: selectedSubject)).tag(direction)
                }
            }
            .pickerStyle(.segmented)

            if selectedBeginnerQuestionLimit > 0 {
                HStack(spacing: 12) {
                    Picker(L("Aufgaben", "Questions"), selection: $selectedBeginnerQuestionLimit) {
                        ForEach(1...300, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 92, height: 104)
                    .clipped()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(beginnerLimitTitle(selectedBeginnerQuestionLimit))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(tealAccentColor)
                        Text(L("Wische am Rad und wähle, was oben angezeigt wird.", "Spin the wheel and choose what is shown at the top."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(L("Der Modus läuft, bis du ihn beendest. Wähle daneben, ob oben Land, Flagge oder Hauptstadt erscheint.", "The mode runs until you stop it. Choose whether country, flag, or capital appears at the top."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .appSurface()
    }

    var beginnerSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Letzte Runde", "Last round"))
                .font(.headline)
            HStack(spacing: 10) {
                beginnerStatTile(title: L("Richtig", "Correct"), value: "\(beginnerSessionCorrect)")
                beginnerStatTile(title: L("Falsch", "Wrong"), value: "\(beginnerSessionWrong)")
                beginnerStatTile(title: L("Quote", "Accuracy"), value: percent(beginnerSessionCorrect, of: beginnerSessionCorrect + beginnerSessionWrong))
            }
        }
        .padding(16)
        .appSurface()
    }

    var beginnerStatsPanel: some View {
        let stats = beginnerStats
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Anfänger-Statistik", "Beginner stats"))
                .font(.headline)
            HStack(spacing: 10) {
                beginnerStatTile(title: L("Runden", "Rounds"), value: "\(stats.roundsPlayed)")
                beginnerStatTile(title: L("Richtig", "Correct"), value: "\(stats.correct)")
                beginnerStatTile(title: L("Quote", "Accuracy"), value: percent(stats.correct, of: stats.answered))
            }
            if stats.bestRoundTotal > 0 {
                Text(L("Beste Runde: \(stats.bestRoundCorrect) / \(stats.bestRoundTotal)", "Best round: \(stats.bestRoundCorrect) / \(stats.bestRoundTotal)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .appSurface()
    }

    func beginnerStatTile(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tealAccentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: AppLayout.controlRadius, style: .continuous))
    }

    var beginnerHistoryBar: some View {
        let includesCurrentQuestion = !beginnerLimitReached
        let maximumResults = includesCurrentQuestion ? 9 : 10
        let visibleResults = beginnerSessionResults.enumerated().suffix(maximumResults)
        let visibleEntryCount = max(visibleResults.count + (includesCurrentQuestion ? 1 : 0), 1)

        return ScaledHistoryBarContainer(entryCount: visibleEntryCount) { pillSize, spacing in
            HStack(spacing: spacing) {
                ForEach(Array(visibleResults), id: \.offset) { _, result in
                    Button {
                        showBeginnerHistoryPreview(result)
                    } label: {
                        PracticeHistoryPill(mark: result.wasKnown ? .known : .unknown, accentColor: tealAccentColor, isSelected: beginnerHistoryPreview?.id == result.id, size: pillSize)
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: pillSize + spacing)
                                .combined(with: .scale(scale: 0.72))
                                .combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                }
                if includesCurrentQuestion {
                    PracticeHistoryPill(
                        mark: .current,
                        accentColor: tealAccentColor,
                        isSelected: false,
                        size: pillSize,
                        animationTrigger: beginnerSessionResults.count
                    )
                }
            }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.7), value: beginnerSessionResults.count)
    }

    func beginnerAnswerName(for country: Country) -> String {
        if selectedSubject == .capitals {
            return selectedBeginnerDirection == .countryToFlag ? capitalName(for: country) : countryName(for: country)
        }
        return countryName(for: country)
    }

    func beginnerQuestionName(for country: Country) -> String {
        selectedSubject == .capitals && selectedBeginnerDirection == .flagToCountry ? capitalName(for: country) : countryName(for: country)
    }

    func beginnerCountryIdentity(country: Country, flagWidth: CGFloat, flagHeight: CGFloat, font: Font) -> some View {
        VStack(spacing: 8) {
            FlagImage(country: country, width: flagWidth, height: flagHeight, isZoomEnabled: false)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.16), lineWidth: 1))
            Text(countryName(for: country))
                .font(font)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
        }
    }

    var beginnerQuestionCard: some View {
        VStack(spacing: 14) {
            if selectedSubject == .countries && selectedBeginnerDirection == .flagToCountry {
                FlagImage(country: beginnerQuestionCountry, width: 320, height: 178, isZoomEnabled: false)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
            } else if selectedSubject == .capitals && selectedBeginnerDirection == .countryToFlag {
                beginnerCountryIdentity(country: beginnerQuestionCountry, flagWidth: 170, flagHeight: 102, font: .title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .padding(12)
                    .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text(beginnerQuestionName(for: beginnerQuestionCountry))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .padding(12)
                    .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
            }

            ZStack {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(beginnerAnswerOptions, id: \.code) { option in
                        beginnerAnswerButton(for: option)
                    }
                }
                .id(beginnerQuestionCountry.code)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
    }

    func beginnerAnswerButton(for option: Country) -> some View {
        let isSelected = beginnerSelectedCountry?.code == option.code
        let isCorrect = option.code == beginnerQuestionCountry.code
        let hasAnswered = beginnerSelectedCountry != nil
        let resultColor: Color? = hasAnswered && isCorrect ? .green : (hasAnswered && isSelected ? .red : nil)
        let resolvedColor = resultColor ?? tealAccentColor

        return Button {
            selectBeginnerAnswer(option)
        } label: {
            Group {
                if selectedSubject == .countries && selectedBeginnerDirection == .countryToFlag {
                    FlagImage(country: option, width: 140, height: 86, isZoomEnabled: false)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                } else if selectedSubject == .capitals && selectedBeginnerDirection == .flagToCountry {
                    beginnerCountryIdentity(country: option, flagWidth: 96, flagHeight: 58, font: .caption.weight(.bold))
                        .padding(.horizontal, 6)
                } else {
                    Text(beginnerAnswerName(for: option))
                        .font(.subheadline.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(
                (resultColor?.opacity(0.18) ?? panelBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(resolvedColor.opacity(resultColor == nil ? 0.28 : 0.95), lineWidth: resultColor == nil ? 1 : 3)
            )
            .overlay(alignment: .topTrailing) {
                if let resultColor {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white, resultColor)
                        .background(Color(.systemBackground), in: Circle())
                        .padding(7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Antwort: \(beginnerAnswerName(for: option))", "Answer: \(beginnerAnswerName(for: option))"))
        .accessibilityValue(
            hasAnswered
                ? (isCorrect ? L("richtig", "correct") : (isSelected ? L("falsch", "incorrect") : ""))
                : ""
        )
        .accessibilityHint(
            hasAnswered
                ? ""
                : L("Doppeltippen, um diese Antwort zu wählen", "Double-tap to choose this answer")
        )
        // Unlike .disabled, hit testing does not visually dim the answers.
        .allowsHitTesting(beginnerSelectedCountry == nil && !beginnerIsAdvancing)
    }

    func beginnerHistoryPopup(for result: BeginnerRoundResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: result.wasKnown ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.wasKnown ? .green : .red)
                Text(result.wasKnown ? L("Richtig", "Correct") : L("Falsch", "Wrong"))
                    .font(.headline.weight(.bold))
                Spacer()
                Button {
                    dismissBeginnerHistoryPreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            if result.subject == .countries && result.direction == .countryToFlag {
                beginnerHistoryCountryLine(
                    L("Aufgabe: \(countryName(for: result.correctCountry))", "Question: \(countryName(for: result.correctCountry))"),
                    country: result.correctCountry
                )
                HStack(spacing: 12) {
                    answerFlagSummary(title: L("Gewählt", "Picked"), country: result.selectedCountry)
                    answerFlagSummary(title: L("Richtig", "Correct"), country: result.correctCountry)
                }
            } else if result.subject == .countries {
                Button {
                    showPracticeHistoryGlobePreview(for: result.correctCountry)
                } label: {
                    FlagImage(country: result.correctCountry, width: 210, height: 118, isZoomEnabled: false)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                beginnerHistoryCountryLine(
                    L("Gewählt: \(countryName(for: result.selectedCountry))", "Picked: \(countryName(for: result.selectedCountry))"),
                    country: result.selectedCountry
                )
                beginnerHistoryCountryLine(
                    L("Richtig: \(countryName(for: result.correctCountry))", "Correct: \(countryName(for: result.correctCountry))"),
                    country: result.correctCountry,
                    color: result.wasKnown ? .green : .red
                )
            } else {
                beginnerHistoryCountryLine(
                    L("Aufgabe: \(result.direction == .countryToFlag ? countryName(for: result.correctCountry) : capitalName(for: result.correctCountry))", "Question: \(result.direction == .countryToFlag ? countryName(for: result.correctCountry) : capitalName(for: result.correctCountry))"),
                    country: result.correctCountry
                )
                beginnerHistoryCountryLine(
                    L("Gewählt: \(result.direction == .countryToFlag ? capitalName(for: result.selectedCountry) : countryName(for: result.selectedCountry))", "Picked: \(result.direction == .countryToFlag ? capitalName(for: result.selectedCountry) : countryName(for: result.selectedCountry))"),
                    country: result.selectedCountry
                )
                beginnerHistoryCountryLine(
                    L("Richtig: \(result.direction == .countryToFlag ? capitalName(for: result.correctCountry) : countryName(for: result.correctCountry))", "Correct: \(result.direction == .countryToFlag ? capitalName(for: result.correctCountry) : countryName(for: result.correctCountry))"),
                    country: result.correctCountry,
                    color: result.wasKnown ? .green : .red
                )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke((result.wasKnown ? Color.green : Color.red).opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    func beginnerHistoryCountryLine(_ text: String, country: Country, color: Color = .primary) -> some View {
        Button {
            showPracticeHistoryGlobePreview(for: country)
        } label: {
            HStack(spacing: 6) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Image(systemName: "globe.europe.africa.fill")
                    .font(.caption)
                    .foregroundStyle(tealAccentColor)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("Öffnet das Land auf dem Globus", "Opens the country on the globe"))
    }

    func answerFlagSummary(title: String, country: Country) -> some View {
        Button {
            showPracticeHistoryGlobePreview(for: country)
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlagImage(country: country, width: 120, height: 72, isZoomEnabled: false)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 4) {
                    Text(countryName(for: country))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.caption2)
                        .foregroundStyle(tealAccentColor)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("Öffnet das Land auf dem Globus", "Opens the country on the globe"))
    }

    func startBeginnerSession() {
        beginnerSessionActive = true
        showBeginnerSummary = false
        beginnerSessionResults = []
        beginnerHistoryPreview = nil
        practiceHistoryGlobeCountry = nil
        beginnerSessionCorrect = 0
        beginnerSessionWrong = 0
        beginnerIsAdvancing = false
        beginnerDisplayedQuestionNumber = 1
        prepareNextBeginnerQuestion()
    }

    func finishBeginnerSession(showSummary: Bool) {
        if !beginnerSessionResults.isEmpty {
            updateActiveProfile { profile in
                profile.recordBeginnerRound(correct: beginnerSessionCorrect, wrong: beginnerSessionWrong)
            }
            checkForUnlockedAchievements()
        }
        beginnerSessionActive = false
        showBeginnerSummary = showSummary && !beginnerSessionResults.isEmpty
        beginnerSelectedCountry = nil
        beginnerIsAdvancing = false
        beginnerHistoryPreview = nil
        practiceHistoryGlobeCountry = nil
    }

    func makeNextBeginnerQuestion() -> (country: Country, options: [Country]) {
        let scopedPool = countries(inContinents: selectedBeginnerContinents)
        // A small selected region can legitimately contain fewer than four
        // countries. Keep the question itself inside the selected scope and
        // widen only the distractors so the mode never silently changes the
        // user's chosen learning area.
        let questionPool = scopedPool.isEmpty ? availableCountries : scopedPool
        let optionPool = questionPool.count >= 4 ? questionPool : availableCountries
        let correct = questionPool.randomElement() ?? allCountries[0]
        let wrongOptions = optionPool
            .filter { $0.code != correct.code }
            .shuffled()
            .prefix(3)
        return (correct, ([correct] + wrongOptions).shuffled())
    }

    func prepareNextBeginnerQuestion() {
        let nextQuestion = makeNextBeginnerQuestion()
        beginnerQuestionCountry = nextQuestion.country
        beginnerAnswerOptions = nextQuestion.options
        beginnerSelectedCountry = nil
    }

    func selectBeginnerAnswer(_ selected: Country) {
        guard beginnerSelectedCountry == nil, !beginnerIsAdvancing else { return }
        beginnerSelectedCountry = selected
        beginnerIsAdvancing = true
        let result = BeginnerRoundResult(country: beginnerQuestionCountry, selectedCountry: selected, correctCountry: beginnerQuestionCountry, direction: selectedBeginnerDirection, subject: selectedSubject)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            beginnerSessionResults.append(result)
            if result.wasKnown {
                beginnerSessionCorrect += 1
            } else {
                beginnerSessionWrong += 1
            }
        }
        Haptics.notify(result.wasKnown ? .success : .error)

        let nextQuestion = beginnerLimitReached ? nil : makeNextBeginnerQuestion()
        let preloadTask = Task { @MainActor in
            guard let nextQuestion else { return }
            await FlagImageCache.shared.warmInMemory(nextQuestion.options + [nextQuestion.country])
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.35))
            await preloadTask.value
            guard beginnerSessionActive,
                  beginnerSessionResults.last?.id == result.id,
                  beginnerSelectedCountry != nil else { return }
            if beginnerLimitReached {
                finishBeginnerSession(showSummary: true)
            } else if let nextQuestion {
                // Old colored answers remain visible until every new flag is
                // ready. The counter follows after the crossfade has finished.
                withAnimation(.easeInOut(duration: 0.3)) {
                    beginnerHistoryPreview = nil
                    beginnerQuestionCountry = nextQuestion.country
                    beginnerAnswerOptions = nextQuestion.options
                    beginnerSelectedCountry = nil
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard beginnerSessionActive,
                      beginnerQuestionCountry.code == nextQuestion.country.code else { return }
                beginnerDisplayedQuestionNumber = beginnerSessionResults.count + 1
                beginnerIsAdvancing = false
            }
        }
    }

    func showBeginnerHistoryPreview(_ result: BeginnerRoundResult) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            practiceHistoryGlobeCountry = nil
            beginnerHistoryPreview = result
        }
    }

    var beginnerEasterEggOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    ForEach(0..<8, id: \.self) { index in
                        Image(systemName: "sparkle")
                            .font(.title3.weight(.black))
                            .foregroundStyle(index.isMultiple(of: 2) ? Color.yellow : tealAccentColor)
                            .offset(y: -58)
                            .rotationEffect(.degrees(Double(index) * 45))
                            .scaleEffect(beginnerEasterEggPulse ? 1.22 : 0.72)
                    }
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(.yellow)
                        .frame(width: 84, height: 84)
                        .background(tealAccentColor.opacity(0.22), in: Circle())
                        .scaleEffect(beginnerEasterEggPulse ? 1.08 : 0.92)
                }
                .frame(width: 150, height: 150)

                Text("Helenas Idee!!!")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(L("Anfänger", "Beginner"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 330)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tealAccentColor.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(.horizontal, 24)
        }
        .onAppear {
            beginnerEasterEggPulse = false
            withAnimation(.easeInOut(duration: 0.34).repeatCount(5, autoreverses: true)) {
                beginnerEasterEggPulse = true
            }
        }
        .onTapGesture {
            hideBeginnerEasterEgg()
        }
    }

    func recordBeginnerEasterEggTap() {
        guard !beginnerSessionActive else { return }
        let now = Date()
        beginnerEasterEggTapDates = (beginnerEasterEggTapDates + [now]).filter { now.timeIntervalSince($0) <= 2.0 }
        guard beginnerEasterEggTapDates.count >= 5 else { return }
        beginnerEasterEggTapDates = []
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            showBeginnerEasterEgg = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            hideBeginnerEasterEgg()
        }
    }

    func hideBeginnerEasterEgg() {
        withAnimation(.easeOut(duration: 0.2)) {
            showBeginnerEasterEgg = false
            beginnerEasterEggPulse = false
        }
    }

    func dismissBeginnerHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            practiceHistoryGlobeCountry = nil
            beginnerHistoryPreview = nil
        }
    }
}
