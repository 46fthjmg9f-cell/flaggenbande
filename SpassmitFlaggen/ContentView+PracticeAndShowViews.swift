import SwiftUI

// MARK: - Practice And Show Views

extension ContentView {
    func adaptiveModeLayout<Content: View>(maxWidth: CGFloat = 560, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width < 360 ? 10 : 16
            ViewThatFits(in: .vertical) {
                content()
                    .padding(horizontalPadding)
                    .frame(maxWidth: maxWidth)
                    .frame(width: geometry.size.width, alignment: .top)

                ScrollView {
                    content()
                        .padding(horizontalPadding)
                        .frame(maxWidth: maxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    var freeDailyFlagLimitInfo: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tealAccentColor)
            Text(L("Heute noch \(freeDailyFlagCardsRemaining) von \(FreeVersionLimits.dailyFlagCards) freien Flaggen", "\(freeDailyFlagCardsRemaining) of \(FreeVersionLimits.dailyFlagCards) free flags left today"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    var practiceView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            adaptiveModeLayout {
                VStack(spacing: 18) {
                modeHeader(title: L("Üben", "Practice"), subtitle: "")
                if !practiceSessionActive {
                    subjectModePickerCard()
                }
                if practiceSessionActive {
                    PracticeHistoryBar(
                        results: practiceSessionResults,
                        changes: practiceSessionChanges,
                        limit: selectedPracticeCardLimit,
                        accentColor: tealAccentColor,
                        selectedChangeID: practiceHistoryPreview?.id,
                        onSelectChange: showPracticeHistoryPreview
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: PracticeHistoryBarMinYKey.self, value: proxy.frame(in: .named("practicePreviewSpace")).minY)
                        }
                    )

                    VStack(spacing: 8) {
                        if practiceRecapPromptIsVisible, let practiceHistoryPreview {
                            practiceHistoryReviewCard(for: practiceHistoryPreview.change)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            practiceSwipeCard
                            Text(L("Wischen!", "Swipe!"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if practiceRecapPromptIsVisible {
                        Button {
                            Haptics.tap()
                            finishPracticeSession(showSummary: true)
                        } label: {
                            Text(L("Weiter", "Continue"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    } else {
                        HStack(spacing: 10) {
                            Button {
                                Haptics.tap()
                                undoLastPracticeSwipe()
                            } label: {
                                Label(L("Rückgängig", "Undo"), systemImage: "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                            .disabled(practiceUndoSnapshot == nil)

                            Button {
                                Haptics.tap()
                                isShowingPracticeCancelConfirmation = true
                            } label: {
                                Text(L("Session abbrechen", "Cancel session"))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                        }
                    }

                    if !practiceRecapPromptIsVisible {
                        hintControl
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Kategorie", "Category"))
                            .font(.headline)
                        continentButtonGrid(selection: $selectedPracticeContinents)
                        if selectedSubject == .countries && !fullVersionUnlocked {
                            freeDailyFlagLimitInfo
                        }
                    }

                    if showRecap {
                        PracticeRecapView(
                            startCounts: recapStartCounts,
                            endCounts: recapEndCounts,
                            known: practiceSessionKnown,
                            unknown: practiceSessionUnknown,
                            improved: practiceSessionImproved,
                            changes: practiceSessionChanges,
                            language: appLanguage,
                            accentColor: tealAccentColor,
                            onRepeat: {
                                Haptics.tap()
                                startPracticeSession()
                            },
                            onDismiss: {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showRecap = false
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if !showRecap {
                        Spacer(minLength: 18)

                        Button {
                            Haptics.tap()
                            startPracticeSession()
                        } label: {
                            Text(L("Starten", "Start"))
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        practiceInfoTile
                    }
                }
            }
        }

            if let practiceHistoryPreview, !practiceRecapPromptIsVisible {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if practiceHistoryGlobeCountry != nil {
                            dismissPracticeHistoryGlobePreview()
                        } else {
                            dismissPracticeHistoryPreview()
                        }
                    }
                    .zIndex(1)

                practiceHistoryFloatingPreview(for: practiceHistoryPreview)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(2)
            }

            if let practiceHistoryGlobeCountry {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissPracticeHistoryGlobePreview()
                    }
                    .zIndex(3)

                practiceHistoryGlobePopup(for: practiceHistoryGlobeCountry)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .zIndex(4)
            }
        }
        .coordinateSpace(name: "practicePreviewSpace")
        .coordinateSpace(name: "historyPreviewSpace")
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: practiceSessionActive)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showRecap)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: practiceHistoryPreview?.id)
        .onPreferenceChange(PracticeHistoryBarMinYKey.self) { value in
            if value > 0 {
                practiceHistoryBarMinY = value
            }
        }
        .onPreferenceChange(SelectedHistoryPillFrameKey.self) { frame in
            selectedHistoryPillFrame = frame
        }
        .onChange(of: selectedPracticeContinents) { _, _ in
            persistPracticeContinents()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                practiceSessionActive = false
                practiceHistoryGlobeCountry = nil
                practiceHistoryPreview = nil
                selectedHistoryPillFrame = nil
            }
        }
    }

    func practiceHistoryReviewCard(for change: PracticeSessionChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(countryName(for: change.country))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
                Image(systemName: "globe.europe.africa.fill")
                    .foregroundStyle(tealAccentColor)
                Text(change.country.code)
                    .font(.caption.weight(.black))
                    .foregroundStyle(tealAccentColor)
            }

            FlagImage(country: change.country, width: 320, height: selectedSubject == .capitals ? 160 : 178, isZoomEnabled: false)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )

            HStack(spacing: 12) {
                MiniLocationGlobe(country: change.country, accentColor: tealAccentColor)
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedScope(change.country.continent))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if selectedSubject == .capitals {
                        Text(capitalName(for: change.country))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tealAccentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    Text(change.wasKnown ? L("Gewusst", "Known") : L("Nicht gewusst", "Not known"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(change.wasKnown ? .green : .red)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(change.wasKnown ? Color.green.opacity(0.28) : Color.red.opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            showPracticeHistoryGlobePreview(for: change.country)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L("Öffnet das Land auf dem Globus", "Opens the country on the globe"))
    }

    func practiceHistoryFloatingPreview(for preview: PracticeHistoryPreview) -> some View {
        historyFloatingPreview(
            for: preview,
            sourceFrame: selectedHistoryPillFrame,
            onDismiss: dismissPracticeHistoryPreview,
            onShowGlobe: { country in showPracticeHistoryGlobePreview(for: country) }
        )
    }

    func historyFloatingPreview(for preview: PracticeHistoryPreview, sourceFrame: CGRect?, onDismiss: @escaping () -> Void, onShowGlobe: @escaping (Country) -> Void) -> some View {
        GeometryReader { geometry in
            if let sourceFrame {
                let screenWidth = geometry.size.width
                let bubbleWidth = min(max(screenWidth - 20, 300), 410)
                let popupHeight: CGFloat = selectedSubject == .capitals ? 214 : 198
                let horizontalMargin: CGFloat = 10
                let arrowWidth: CGFloat = 26
                let popupGap: CGFloat = 6
                let selectedCenterX = sourceFrame.midX
                let bubbleLeft = min(max(selectedCenterX - bubbleWidth / 2, horizontalMargin), screenWidth - bubbleWidth - horizontalMargin)
                let arrowX = min(max(selectedCenterX - bubbleLeft, arrowWidth / 2), bubbleWidth - arrowWidth / 2)
                let popupTop = sourceFrame.maxY + popupGap

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                            .frame(width: arrowX - arrowWidth / 2)
                        Triangle()
                            .fill(.ultraThinMaterial)
                            .frame(width: arrowWidth, height: 14)
                            .overlay(
                                Triangle()
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                        Spacer(minLength: 0)
                    }
                    .frame(width: bubbleWidth)

                    historyPreview(for: preview.change, onShowGlobe: onShowGlobe)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                Haptics.tap()
                                onDismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                }
                .frame(width: bubbleWidth)
                .position(x: bubbleLeft + bubbleWidth / 2, y: popupTop + popupHeight / 2)
            } else {
                Color.clear
            }
        }
    }

    func historyGlobeTiers(highlightedCountry: Country) -> [String: MasteryTier] {
        Dictionary(uniqueKeysWithValues: availableCountries.map { country in
            (country.code, country.code == highlightedCountry.code ? MasteryTier.s : MasteryTier.b)
        })
    }

    func practiceHistoryGlobePopup(for country: Country) -> some View {
        GeometryReader { geometry in
            let width = min(max(geometry.size.width - 28, 300), 390)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(countryName(for: country))
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)

                    Text(country.code)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tealAccentColor, in: Capsule())
                }

                GlobeSceneView(
                    countries: availableCountries,
                    tiersByCountryCode: historyGlobeTiers(highlightedCountry: country),
                    resetToken: 0,
                    focusCountryCode: country.code,
                    highlightCountryCode: country.code,
                    persistsViewState: false,
                    onSelectCountryCode: { _ in }
                )
                .frame(height: min(width * 0.82, 300))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
            }
            .padding(12)
            .frame(width: width)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .position(x: geometry.size.width / 2, y: 180)
        }
        .frame(height: 360)
    }

    func practiceHistoryPreview(for change: PracticeSessionChange) -> some View {
        historyPreview(for: change) { country in
            showPracticeHistoryGlobePreview(for: country)
        }
    }

    func historyPreview(for change: PracticeSessionChange, onShowGlobe: @escaping (Country) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onShowGlobe(change.country)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    FlagImage(country: change.country, width: 82, height: 56, isZoomEnabled: false)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )

                    MiniLocationGlobe(country: change.country, accentColor: tealAccentColor)
                        .frame(width: 108, height: 108)
                        .frame(width: 112)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(countryName(for: change.country))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                            Image(systemName: "globe.europe.africa.fill")
                                .font(.caption)
                                .foregroundStyle(tealAccentColor)
                        }
                        Text(localizedScope(change.country.continent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if selectedSubject == .capitals {
                            Text(capitalName(for: change.country))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tealAccentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Öffnet das Land auf dem Globus", "Opens the country on the globe"))

            HStack(spacing: 8) {
                Label(change.wasKnown ? L("Gewusst", "Known") : L("Nicht gewusst", "Not known"), systemImage: change.wasKnown ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change.wasKnown ? .green : .red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background((change.wasKnown ? Color.green : Color.red).opacity(0.12), in: Capsule())

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    tierMiniBadge(change.fromTier)
                    Image(systemName: change.wasKnown ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(change.wasKnown ? .green : .red)
                    tierMiniBadge(change.toTier)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(change.wasKnown ? Color.green.opacity(0.32) : Color.red.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    func tierMiniBadge(_ tier: MasteryTier) -> some View {
        Text(tier.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tier.color, in: RoundedRectangle(cornerRadius: 6))
    }

    func swipeableStudyCard(
        dragOffset: Binding<CGFloat>,
        entryOffset: Binding<CGFloat>,
        entryOpacity: Binding<Double>,
        isFinishingSwipe: Binding<Bool>,
        isInteractionBlocked: Bool,
        onFinishSwipe: @escaping (CGSize, CGSize) -> Void
    ) -> some View {
        let swipeColor: Color = dragOffset.wrappedValue >= 0 ? .green : .red
        let swipeOpacity = min(abs(Double(dragOffset.wrappedValue)) / 140, 0.35)

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(swipeColor.opacity(swipeOpacity))
                .frame(height: 260)
                .overlay(alignment: dragOffset.wrappedValue >= 0 ? .leading : .trailing) {
                    Image(systemName: dragOffset.wrappedValue >= 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(swipeColor)
                        .opacity(swipeOpacity)
                        .padding(.horizontal, 26)
                }

            FlipCard(country: currentCountry, isFlipped: cardIsFlipped, hasGoldAura: tier(for: currentCountry) == .s, language: appLanguage, subject: selectedSubject, capital: capitalName(for: currentCountry))
                .id(currentCountry.id)
                .offset(x: dragOffset.wrappedValue, y: entryOffset.wrappedValue)
                .opacity((isFinishingSwipe.wrappedValue ? 0.82 : 1) * entryOpacity.wrappedValue)
                .scaleEffect(entryOpacity.wrappedValue < 1 ? 0.985 : 1)
                .rotationEffect(.degrees(max(min(Double(dragOffset.wrappedValue / 22), 10), -10)))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: currentCountry.id)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: entryOffset.wrappedValue)
                .animation(.easeOut(duration: 0.2), value: entryOpacity.wrappedValue)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard !isFinishingSwipe.wrappedValue, !isInteractionBlocked else { return }
                            guard !FlagZoomInteractionState.isPinching else {
                                dragOffset.wrappedValue = 0
                                return
                            }
                            dragOffset.wrappedValue = max(min(value.translation.width, 220), -220)
                        }
                        .onEnded { value in
                            guard !isInteractionBlocked else {
                                dragOffset.wrappedValue = 0
                                return
                            }
                            guard !FlagZoomInteractionState.isPinching else {
                                dragOffset.wrappedValue = 0
                                return
                            }
                            onFinishSwipe(value.translation, value.predictedEndTranslation)
                        }
                )

        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard !isFinishingSwipe.wrappedValue, !isInteractionBlocked, !FlagZoomInteractionState.isPinching else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardIsFlipped.toggle()
            }
        }
    }

    func showPracticeHistoryPreview(_ preview: PracticeHistoryPreview) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            practiceHistoryGlobeCountry = nil
            selectedHistoryPillFrame = nil
            practiceHistoryPreview = preview
        }
    }

    func dismissPracticeHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            practiceHistoryGlobeCountry = nil
            practiceHistoryPreview = nil
            selectedHistoryPillFrame = nil
        }
    }

    func showPracticeHistoryGlobePreview(for country: Country) {
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            practiceHistoryGlobeCountry = country
        }
    }

    func dismissPracticeHistoryGlobePreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            practiceHistoryGlobeCountry = nil
        }
    }

    func showShowmasterHistoryPreview(_ preview: PracticeHistoryPreview) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            practiceHistoryGlobeCountry = nil
            selectedHistoryPillFrame = nil
            showHistoryPreview = preview
        }
    }

    func dismissShowmasterHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            practiceHistoryGlobeCountry = nil
            showHistoryPreview = nil
            selectedHistoryPillFrame = nil
        }
    }

    var practiceInfoTile: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(tealAccentColor)
            Text(L("Flaggen und Hauptstädte, die du gut kannst, kommen seltener. Wenn du eine Karte 3 Tage nicht als gewusst loggst, fällt sie eine Stufe runter. Unsichere Karten tauchen häufiger auf, damit du sie schneller lernst.", "Flags and capitals you know well appear less often. If you do not log a card as known for 3 days, it drops one level. Uncertain cards show up more frequently so you learn them faster."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var practiceSwipeCard: some View {
        ZStack {
            swipeableStudyCard(
                dragOffset: $practiceCardDragOffset,
                entryOffset: $practiceCardEntryOffset,
                entryOpacity: $practiceCardEntryOpacity,
                isFinishingSwipe: $isFinishingPracticeSwipe,
                isInteractionBlocked: practiceRecapPromptIsVisible,
                onFinishSwipe: { translation, predictedTranslation in
                    finishPracticeSwipe(translation: translation, predictedTranslation: predictedTranslation)
                }
            )

            if hintBlockFeedbackIsVisible {
                Label(L("Mit Tipp nur als nicht gewusst möglich", "With a hint, only not known is possible"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.94), in: Capsule())
                    .shadow(color: .orange.opacity(0.28), radius: 12, y: 5)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            }
        }
    }

    var hintControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                activateHint()
            } label: {
                Label(cardHintIsVisible ? L("Tipp aktiviert", "Hint active") : L("Tipp anzeigen", "Show hint"), systemImage: cardHintIsVisible ? "lightbulb.fill" : "lightbulb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cardHintIsVisible ? .orange : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(practiceRecapPromptIsVisible)
            .background(Color(.secondarySystemFill).opacity(cardHintIsVisible ? 0.45 : 0.32), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(cardHintIsVisible ? Color.orange.opacity(0.34) : Color.secondary.opacity(0.12), lineWidth: 1)
            )

            if cardHintIsVisible {
                VStack(alignment: .leading, spacing: 7) {
                    Text(hintText(for: currentCountry))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Diese Karte kann jetzt nicht mehr als gewusst geloggt werden.", "This card can no longer be logged as known."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.26), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: cardHintIsVisible)
    }

    var showRandomnessControl: some View {
        Toggle(isOn: $showAvoidsRecentRepeats) {
            VStack(alignment: .leading, spacing: 3) {
                Label(L("Wiederholungen vermeiden", "Avoid repeats"), systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                Text(showAvoidsRecentRepeats ? L("Alle verfügbaren Karten kommen erst einmal dran, bevor neu gemischt wird.", "Every available card appears once before shuffling again.") : L("Komplett zufällig.", "Completely random."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var showSwipeCard: some View {
        ZStack {
            swipeableStudyCard(
                dragOffset: $showCardDragOffset,
                entryOffset: $showCardEntryOffset,
                entryOpacity: $showCardEntryOpacity,
                isFinishingSwipe: $isFinishingShowSwipe,
                isInteractionBlocked: showLimitReached,
                onFinishSwipe: { translation, predictedTranslation in
                    finishShowSwipe(translation: translation, predictedTranslation: predictedTranslation)
                }
            )

            if hintBlockFeedbackIsVisible {
                Label(L("Mit Tipp nur als nicht gewusst möglich", "With a hint, only not known is possible"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.94), in: Capsule())
                    .shadow(color: .orange.opacity(0.28), radius: 12, y: 5)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            }
        }
    }

    var showView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            adaptiveModeLayout {
                VStack(spacing: 18) {
                modeHeader(title: "Showmaster", subtitle: "")
                subjectModePickerCard()

                if showSessionActive {
                    Text(showSessionProgressText())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    PracticeHistoryBar(
                        results: showSessionEntries.map(\.wasKnown),
                        changes: showSessionEntries,
                        limit: selectedShowCardLimit,
                        accentColor: tealAccentColor,
                        selectedChangeID: showHistoryPreview?.id,
                        onSelectChange: showShowmasterHistoryPreview
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ShowHistoryBarMinYKey.self, value: proxy.frame(in: .named("showPreviewSpace")).minY)
                        }
                    )

                    VStack(spacing: 8) {
                        showSwipeCard
                        Text(L("Wischen!", "Swipe!"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            undoLastShowSwipe()
                        } label: {
                            Label(L("Rückgängig", "Undo"), systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                        .disabled(showUndoSnapshot == nil)

                        Button {
                            Haptics.tap()
                            isShowingShowCancelConfirmation = true
                        } label: {
                            Text(L("Abbrechen", "Cancel"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    }

                    hintControl
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Kategorie", "Category"))
                            .font(.headline)
                        continentButtonGrid(selection: $selectedShowContinents)
                        if selectedSubject == .countries && !fullVersionUnlocked {
                            freeDailyFlagLimitInfo
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Karten", "Cards"))
                            .font(.headline)
                        cardLimitSelector(selection: $selectedShowCardLimit)
                    }

                    showRandomnessControl

                    Spacer(minLength: 18)

                    Button {
                        Haptics.tap()
                        startShowSession()
                    } label: {
                        Text(L("Starten", "Start"))
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    .padding(.top, 8)
                }
            }
        }
            if let showHistoryPreview {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if practiceHistoryGlobeCountry != nil {
                            dismissPracticeHistoryGlobePreview()
                        } else {
                            dismissShowmasterHistoryPreview()
                        }
                    }
                    .zIndex(1)

                historyFloatingPreview(
                    for: showHistoryPreview,
                    sourceFrame: selectedHistoryPillFrame,
                    onDismiss: dismissShowmasterHistoryPreview,
                    onShowGlobe: { country in showPracticeHistoryGlobePreview(for: country) }
                )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(2)
            }

            if let practiceHistoryGlobeCountry, showHistoryPreview != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissPracticeHistoryGlobePreview()
                    }
                    .zIndex(3)

                practiceHistoryGlobePopup(for: practiceHistoryGlobeCountry)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .zIndex(4)
            }
        }
        .coordinateSpace(name: "showPreviewSpace")
        .coordinateSpace(name: "historyPreviewSpace")
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: showHistoryPreview?.id)
        .onPreferenceChange(ShowHistoryBarMinYKey.self) { value in
            if value > 0 {
                showHistoryBarMinY = value
            }
        }
        .onPreferenceChange(SelectedHistoryPillFrameKey.self) { frame in
            selectedHistoryPillFrame = frame
        }
        .onChange(of: selectedShowContinents) { _, _ in
            resetShowSession(clearDeck: true)
        }
        .onChange(of: selectedShowCardLimit) { _, _ in
            resetShowSession()
        }
    }
}
