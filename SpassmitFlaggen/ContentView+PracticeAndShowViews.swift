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
                                finishPracticeSession(showSummary: practiceSessionCount > 0)
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
                    .padding(.top, practiceHistoryBarMinY + 38)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(2)
            }

            if let practiceHistoryGlobeCountry, !practiceRecapPromptIsVisible {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissPracticeHistoryGlobePreview()
                    }
                    .zIndex(3)

                practiceHistoryGlobePopup(for: practiceHistoryGlobeCountry)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, practiceHistoryBarMinY + 238)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .zIndex(4)
            }
        }
        .coordinateSpace(name: "practicePreviewSpace")
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: practiceSessionActive)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showRecap)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: practiceHistoryPreview?.id)
        .onPreferenceChange(PracticeHistoryBarMinYKey.self) { value in
            if value > 0 {
                practiceHistoryBarMinY = value
            }
        }
        .onChange(of: selectedPracticeContinents) { _, _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                practiceSessionActive = false
                practiceHistoryGlobeCountry = nil
                practiceHistoryPreview = nil
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
                    .frame(width: 76, height: 76)
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
    }

    func practiceHistoryFloatingPreview(for preview: PracticeHistoryPreview) -> some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let bubbleWidth = min(max(screenWidth - 20, 300), 410)
            let popupHeight: CGFloat = selectedSubject == .capitals ? 204 : 188
            let barHorizontalPadding: CGFloat = 10
            let pillWidth: CGFloat = 28
            let pillSpacing: CGFloat = 7
            let entriesWidth = CGFloat(preview.total) * pillWidth + CGFloat(max(preview.total - 1, 0)) * pillSpacing
            let entriesStart = (screenWidth - entriesWidth) / 2
            let selectedCenterX = entriesStart + CGFloat(preview.index) * (pillWidth + pillSpacing) + pillWidth / 2
            let bubbleLeft = min(max(selectedCenterX - bubbleWidth / 2, barHorizontalPadding), screenWidth - bubbleWidth - barHorizontalPadding)
            let arrowX = min(max(selectedCenterX - bubbleLeft, 24), bubbleWidth - 24)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(width: arrowX - 13)
                    Triangle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 26, height: 14)
                        .overlay(
                            Triangle()
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
                .frame(width: bubbleWidth)

                practiceHistoryPreview(for: preview.change)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            Haptics.tap()
                            dismissPracticeHistoryPreview()
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
            .position(x: bubbleLeft + bubbleWidth / 2, y: popupHeight / 2)
        }
        .frame(height: selectedSubject == .capitals ? 204 : 188)
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
                    countries: [country],
                    tiersByCountryCode: [country.code: .s],
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                FlagImage(country: change.country, width: 82, height: 56, isZoomEnabled: false)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )

                Button {
                    showPracticeHistoryGlobePreview(for: change.country)
                } label: {
                    VStack(spacing: 5) {
                        MiniLocationGlobe(country: change.country, accentColor: tealAccentColor)
                            .frame(width: 94, height: 94)
                        Text(change.country.code)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(tealAccentColor)
                    }
                    .frame(width: 98)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(countryName(for: change.country))
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
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

                Spacer(minLength: 0)
            }

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

    func showPracticeHistoryPreview(_ preview: PracticeHistoryPreview) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            practiceHistoryGlobeCountry = nil
            practiceHistoryPreview = preview
        }
    }

    func dismissPracticeHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            practiceHistoryGlobeCountry = nil
            practiceHistoryPreview = nil
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

    func showHistoryPreviewBubble(for preview: ShowHistoryPreview) -> some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let horizontalMargin: CGFloat = 12
            let outerPadding: CGFloat = 16
            let barInnerPadding: CGFloat = 10
            let pillWidth: CGFloat = 28
            let pillSpacing: CGFloat = 7
            let bubbleWidth = min(max(screenWidth - horizontalMargin * 2, 260), 360)
            let contentMaxWidth = min(screenWidth - outerPadding * 2, 520)
            let contentStart = (screenWidth - contentMaxWidth) / 2
            let barContentWidth = max(contentMaxWidth - barInnerPadding * 2, 1)
            let entriesWidth = CGFloat(preview.total) * pillWidth + CGFloat(max(preview.total - 1, 0)) * pillSpacing
            let entriesStart = contentStart + barInnerPadding + max((barContentWidth - entriesWidth) / 2, 0)
            let selectedCenterX = entriesStart + CGFloat(preview.index) * (pillWidth + pillSpacing) + pillWidth / 2
            let bubbleLeft = min(max(selectedCenterX - bubbleWidth / 2, horizontalMargin), screenWidth - bubbleWidth - horizontalMargin)
            let arrowX = min(max(selectedCenterX - bubbleLeft, 24), bubbleWidth - 24)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: arrowX - 13)
                    Triangle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 26, height: 14)
                        .overlay(
                            Triangle()
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
                .frame(width: bubbleWidth)

                showHistoryPreviewContent(for: preview.entry.country)
            }
            .frame(width: bubbleWidth)
            .position(x: bubbleLeft + bubbleWidth / 2, y: 73)
        }
        .frame(height: 146)
        .onTapGesture {
            dismissShowmasterHistoryPreview()
        }
    }

    func showHistoryPreviewContent(for country: Country) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FlagImage(country: country, width: 74, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )

            MiniLocationGlobe(country: country, accentColor: tealAccentColor)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(countryName(for: country))
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(localizedScope(country.continent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if selectedSubject == .capitals {
                    Text(capitalName(for: country))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tealAccentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Text("Showmaster")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tealAccentColor)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            dismissShowmasterHistoryPreview()
        }
    }

    func showShowmasterHistoryPreview(_ preview: ShowHistoryPreview) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            showHistoryPreview = preview
        }
    }

    func dismissShowmasterHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            showHistoryPreview = nil
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
            RoundedRectangle(cornerRadius: 12)
                .fill(practiceSwipeColor.opacity(practiceSwipeOpacity))
                .frame(height: 260)
                .overlay(alignment: practiceCardDragOffset >= 0 ? .leading : .trailing) {
                    Image(systemName: practiceCardDragOffset >= 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(practiceCardDragOffset >= 0 ? .green : .red)
                        .opacity(practiceSwipeOpacity)
                        .padding(.horizontal, 26)
                }

            FlipCard(country: currentCountry, isFlipped: cardIsFlipped, hasGoldAura: tier(for: currentCountry) == .s, language: appLanguage, subject: selectedSubject, capital: capitalName(for: currentCountry))
                .id(currentCountry.id)
                .offset(x: practiceCardDragOffset, y: practiceCardEntryOffset)
                .opacity((isFinishingPracticeSwipe ? 0.82 : 1) * practiceCardEntryOpacity)
                .scaleEffect(practiceCardEntryOpacity < 1 ? 0.985 : 1)
                .rotationEffect(.degrees(max(min(Double(practiceCardDragOffset / 22), 10), -10)))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: currentCountry.id)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: practiceCardEntryOffset)
                .animation(.easeOut(duration: 0.2), value: practiceCardEntryOpacity)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard !isFinishingPracticeSwipe, !practiceRecapPromptIsVisible else { return }
                            guard !FlagZoomInteractionState.isPinching else {
                                practiceCardDragOffset = 0
                                return
                            }
                            practiceCardDragOffset = max(min(value.translation.width, 220), -220)
                        }
                        .onEnded { value in
                            guard !practiceRecapPromptIsVisible else {
                                practiceCardDragOffset = 0
                                return
                            }
                            guard !FlagZoomInteractionState.isPinching else {
                                practiceCardDragOffset = 0
                                return
                            }
                            finishPracticeSwipe(translation: value.translation, predictedTranslation: value.predictedEndTranslation)
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
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard !isFinishingPracticeSwipe, !practiceRecapPromptIsVisible, !FlagZoomInteractionState.isPinching else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardIsFlipped.toggle()
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

    var practiceSwipeColor: Color {
        practiceCardDragOffset >= 0 ? .green : .red
    }

    var practiceSwipeOpacity: Double {
        min(abs(Double(practiceCardDragOffset)) / 140, 0.35)
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

                    ShowHistoryBar(
                        entries: showSessionEntries,
                        limit: selectedShowCardLimit,
                        accentColor: tealAccentColor,
                        selectedEntryID: showHistoryPreview?.id,
                        onSelectEntry: showShowmasterHistoryPreview
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ShowHistoryBarMinYKey.self, value: proxy.frame(in: .named("showPreviewSpace")).minY)
                        }
                    )

                    FlipCard(country: currentCountry, isFlipped: cardIsFlipped, hasGoldAura: tier(for: currentCountry) == .s, language: appLanguage, subject: selectedSubject, capital: capitalName(for: currentCountry))
                        .id(currentCountry.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.easeInOut(duration: 0.22), value: currentCountry.id)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                cardIsFlipped.toggle()
                            }
                        }
                    Button {
                        Haptics.tap()
                        nextShowCard()
                    } label: {
                        Text(L("Nächste Flagge", "Next flag"))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    .disabled(showLimitReached)

                    Button {
                        Haptics.tap()
                        isShowingShowCancelConfirmation = true
                    } label: {
                        Text(L("Abbrechen", "Cancel"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(ActionButtonStyle(color: tealAccentColor))

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
                        dismissShowmasterHistoryPreview()
                    }
                    .zIndex(1)

                showHistoryPreviewBubble(for: showHistoryPreview)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, showHistoryBarMinY + 38)
                    .transition(.scale(scale: 0.25, anchor: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .coordinateSpace(name: "showPreviewSpace")
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: showHistoryPreview?.id)
        .onPreferenceChange(ShowHistoryBarMinYKey.self) { value in
            if value > 0 {
                showHistoryBarMinY = value
            }
        }
        .onAppear { resetShowSession() }
        .onChange(of: selectedShowContinents) { _, _ in
            resetShowSession(clearDeck: true)
        }
        .onChange(of: selectedShowCardLimit) { _, _ in
            resetShowSession()
        }
    }
}
