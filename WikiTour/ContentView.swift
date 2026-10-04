import SwiftUI
import MapKit

struct ContentView: View {
    @State private var viewModel = makeViewModel()

    var body: some View {
        GeometryReader { geometry in
            TourMapView(viewModel: viewModel)
                .environment(\.tourBottomInset, geometry.safeAreaInsets.bottom)
                // Brandon Text is the app's default font; views set specific Brandon styles.
                .font(.brandon(17))
                .tint(.accentColor)
                .task { viewModel.start() }
        }
    }
    @MainActor
    private static func makeViewModel() -> TourViewModel {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            let suite = "WikiTour.UITests"
            let defaults = UserDefaults(suiteName: suite)!
            if arguments.contains("--reset-saved") { defaults.removePersistentDomain(forName: suite) }
            return TourViewModel(defaults: defaults) { from, to in
                // Deterministic transport exclusively for UI tests, never live navigation.
                WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 800, duration: 600)
            }
        }
        #endif
        return TourViewModel()
    }

}

/// The mocks deliberately pair a dark map with a light gray reading surface.
enum TourStyle {
    // Resolve the named asset directly: MapKit overlays do not inherit SwiftUI accent tint reliably.
    static let accent = Color("AccentColor")
    static let savedMarkerFill = Color("SavedMarkerFill")
    static let paper = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)
    static let ink = Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255)
}

/// A bottom-anchored surface whose width is independent of system modal margins.
struct EdgeToEdgeSheet<Content: View>: View {
    let initialFraction: CGFloat
    var allowsCollapsed = false
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.tourBottomInset) private var bottomInset
    @State private var selectedDetent = 1
    @State private var dragStartHeight: CGFloat?
    @State private var draggedHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let safeBottom = max(bottomInset, geometry.safeAreaInsets.bottom)
            let maximum = max(160, geometry.size.height - 8)
            let middle = maximum * initialFraction
            let heights: [CGFloat] = [allowsCollapsed ? 72 + safeBottom : middle, middle, maximum]
            let height = min(maximum, max(60, draggedHeight ?? heights[selectedDetent]))

            VStack(spacing: 0) {
                content()
                    .environment(\.isTourSheetCollapsed, allowsCollapsed && selectedDetent == 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TourStyle.paper.frame(height: safeBottom)
            }
            .frame(width: geometry.size.width, height: height)
            .background(TourStyle.paper)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
            .overlay(alignment: .top) {
                Capsule().fill(TourStyle.ink.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .frame(width: 200, height: 32)
                    .frame(height: 44, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { changeDetent(selectedDetent == 2 ? 1 : selectedDetent == 1 && allowsCollapsed ? 0 : 2) }
                    .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { value in
                            // The handle moves with the sheet; local coordinates feed that
                            // movement back into the gesture and make the drawer oscillate.
                            let start = dragStartHeight ?? heights[selectedDetent]
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                dragStartHeight = start
                                draggedHeight = start - value.translation.height
                            }
                        }
                        .onEnded { value in
                            let start = dragStartHeight ?? heights[selectedDetent]
                            let actual = start - value.translation.height
                            let target = start - value.predictedEndTranslation.height
                            // Velocity can choose a detent, but cannot accidentally dismiss
                            // a walk. Other drawers require a deliberate pull below minimum.
                            if !allowsCollapsed && actual < heights[1] * 0.55 {
                                onClose()
                            } else {
                                let indices = allowsCollapsed ? Array(0...2) : Array(1...2)
                                let nearest = indices.min { abs(heights[$0] - target) < abs(heights[$1] - target) } ?? 1
                                changeDetent(nearest)
                            }
                        })
                    .accessibilityElement()
                    .accessibilityLabel("Sheet size")
                    .accessibilityValue(selectedDetent == 2 ? "Expanded" : selectedDetent == 0 && allowsCollapsed ? "Collapsed" : "Half screen")
                    .accessibilityHint("Double tap to resize the sheet")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: changeDetent(min(2, selectedDetent + 1))
                        case .decrement: changeDetent(max(allowsCollapsed ? 0 : 1, selectedDetent - 1))
                        @unknown default: break
                        }
                    }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("edgeToEdgeSheet")
            .accessibilityAction(.escape, onClose)
            .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .environment(\.colorScheme, .light)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func changeDetent(_ index: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
            selectedDetent = index
            // Release from the last rendered height in the same animation transaction.
            draggedHeight = nil
            dragStartHeight = nil
        }
    }
}

private struct TourSheetCollapsedKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var isTourSheetCollapsed: Bool {
        get { self[TourSheetCollapsedKey.self] }
        set { self[TourSheetCollapsedKey.self] = newValue }
    }
}

private struct TourBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var tourBottomInset: CGFloat {
        get { self[TourBottomInsetKey.self] }
        set { self[TourBottomInsetKey.self] = newValue }
    }
}
