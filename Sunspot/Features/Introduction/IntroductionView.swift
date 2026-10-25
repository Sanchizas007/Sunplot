import SwiftUI
import SpotKit
import Observation

// MARK: - What is on screen, and what the app owes the person afterwards

/// Whether the tour is in front of the person, and whether it is the first one.
///
/// The first launch's tour has a job beyond explaining: it is where the app asks where the
/// person is. That question used to arrive as a bare system dialog over an empty screen, from
/// an app nobody had yet had a chance to understand, so it now waits until the tour is done.
/// The replay from the menu is only the explanation and asks nothing.
@MainActor
@Observable
final class IntroductionFlow {

    private(set) var isPresented: Bool
    private(set) var isFirstRun: Bool

    /// The page to open on. Always the first, except for a screenshot run checking one.
    let startPage: Int

    init(hasSpots: Bool) {
        if let page = Demo.introPage {
            isPresented = true
            isFirstRun = Demo.introIsFirstRun
            startPage = page
        } else if Demo.isRunning {
            isPresented = false
            isFirstRun = false
            startPage = 0
        } else {
            let show = Introduction.shouldShowAtLaunch(hasSeen: Introduction.hasBeenSeen, hasSpots: hasSpots)
            isPresented = show
            isFirstRun = show
            startPage = 0
        }
    }

    /// Closes the tour. Returns whether it was the first one, because that is the moment the
    /// app goes and asks where the person is.
    @discardableResult
    func finish() -> Bool {
        Introduction.markSeen()
        let wasFirst = isFirstRun
        isFirstRun = false
        isPresented = false
        return wasFirst
    }

    func replay() {
        isFirstRun = false
        isPresented = true
    }
}

// MARK: - Pages

enum IntroPage: Int, CaseIterable, Identifiable {
    case question, path, skyline, map, place

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .question: "How much sun does this spot get?"
        case .path:     "The yellow line is the sun's path"
        case .skyline:  "Trace what is in the way"
        case .map:      "Read the lines on the map"
        case .place:    "Where is the spot?"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .question:
            "Sunplot counts the hours of direct sunlight a spot really gets, once the roofs and trees have taken their share."
        case .path:
            "Point the phone at the sky. The line is where the sun travels today, and the disc is where it is right now."
        case .skyline:
            "Keep a finger on the tops of the roofs and trees and turn on the spot. Only the sun above that line counts."
        case .map:
            "Orange is where the sun arrives from, pink is where it leaves, yellow is where it is now. Slide the time to move through the day."
        case .place:
            "Sunplot needs your position to work out where the sun travels overhead. It stays on this phone — there is no server to send it to."
        }
    }
}

// MARK: - Look

enum IntroStyle {
    /// The dark of the icon's rooftops. Everything the tour stands on, and the colour its
    /// silhouettes are cut from, so a roof meets the page without a seam.
    static let ground = Color(red: 0.086, green: 0.071, blue: 0.106)
    static let amber = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let orange = Color(red: 0.99, green: 0.52, blue: 0.13)
}

private struct IntroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Dark on amber rather than white on orange: nine to one against three to one.
            .foregroundStyle(Color(red: 0.16, green: 0.09, blue: 0.05))
            .background(
                Capsule().fill(
                    LinearGradient(colors: [IntroStyle.amber, IntroStyle.orange], startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: IntroStyle.orange.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? IntroStyle.amber : Color.white.opacity(0.28))
                    .frame(width: index == current ? 26 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.35), value: current)
        // One element that says where you are, rather than five that say nothing.
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(current + 1) / \(count)")
    }
}

// MARK: - The tour

struct IntroductionView: View {
    let isFirstRun: Bool
    let onFinish: () -> Void

    @State private var page: IntroPage

    init(startPage: Int = 0, isFirstRun: Bool, onFinish: @escaping () -> Void) {
        self.isFirstRun = isFirstRun
        self.onFinish = onFinish
        _page = State(initialValue: IntroPage(rawValue: startPage) ?? .question)
    }

    private var isLast: Bool { page == IntroPage.allCases.last }

    var body: some View {
        ZStack {
            IntroStyle.ground.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(IntroPage.allCases) { item in
                    IntroPageView(page: item, isActive: item == page)
                        .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { controls }
        .overlay(alignment: .topTrailing) { topButton }
        .sensoryFeedback(.selection, trigger: page)
        // The tour is dark whatever the phone is set to: the sky it draws is meant to be seen
        // against night, and the materials it uses should match.
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
    }

    private var controls: some View {
        VStack(spacing: 20) {
            PageDots(count: IntroPage.allCases.count, current: page.rawValue)

            Button(action: advance) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(IntroButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
    }

    /// Skip on the first run, because somebody who knows what a sun app is should not be made
    /// to sit through one; Done on a replay, because there is nothing to skip to.
    @ViewBuilder
    private var topButton: some View {
        if isFirstRun && !isLast {
            Button(action: onFinish) {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
            .padding(.trailing, 20)
        } else if !isFirstRun {
            Button(action: onFinish) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
            .padding(.trailing, 20)
        }
    }

    private var buttonTitle: LocalizedStringKey {
        guard isLast else { return "Next" }
        return isFirstRun ? "Show me my sun" : "Done"
    }

    private func advance() {
        guard !isLast, let next = IntroPage(rawValue: page.rawValue + 1) else {
            onFinish()
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) { page = next }
    }
}

// MARK: - One page

private struct IntroPageView: View {
    let page: IntroPage
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                IntroArt(page: page, isActive: isActive, topInset: max(proxy.safeAreaInsets.top, 44))
                    // Tall phones give the picture just over half the screen. A short one cannot
                    // afford that: the title, the text and the buttons need about 350 points, and the
                    // picture is what gives way.
                    .frame(height: max(250, min(proxy.size.height * 0.54, proxy.size.height - 350)))
                    .clipped()
                    .accessibilityHidden(true)

                // A scroll view only so that the largest accessibility type has somewhere to
                // go; at any ordinary size it does not move.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.title)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text(page.message)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Room underneath for the dots and the button, which sit above every page.
                .contentMargins(.bottom, 130, for: .scrollContent)
            }
        }
        // The sky runs up under the Dynamic Island. Page-style tab views lay their pages out
        // inside the safe area whatever the tab view itself says, so the page has to ask.
        .ignoresSafeArea()
    }
}
