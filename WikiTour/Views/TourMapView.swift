import SwiftUI
import MapKit

private enum MapSheet: Identifiable {
    case place(Landmark), saved, walks, walk
    var id: String {
        switch self {
        case .place(let landmark): return landmark.id
        case .saved: return "saved"
        case .walks: return "walks"
        case .walk: return "walk"
        }
    }
}

struct TourMapView: View {
    let viewModel: TourViewModel
    @State private var sheet: MapSheet?
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: .init(latitude: 40.666, longitude: -73.984),
        span: .init(latitudeDelta: 0.024, longitudeDelta: 0.018)))
    @State private var visibleCenter = CLLocationCoordinate2D(latitude: 40.666, longitude: -73.984)
    @State private var visibleRegion = MKCoordinateRegion(center: .init(latitude: 40.666, longitude: -73.984), span: .init(latitudeDelta: 0.024, longitudeDelta: 0.018))
    @State private var viewport = CGSize(width: 402, height: 874)
    @State private var hasMoved = false
    @State private var cameraDistance: Double = 4800
    @State private var cameraHeading: Double = 0
    /// Where the map last zoomed to fit a tour. Moving away from the search or from this automatic
    /// position is what offers "Search this area".
    @State private var fittedCenter: CLLocationCoordinate2D?
    @Environment(\.tourBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            UserAnnotation()
            ForEach(Array(viewModel.routeLines.enumerated()), id: \.offset) { _, line in
                MapPolyline(line)
                    .stroke(TourStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            ForEach(placedLandmarks) { placement in
                let landmark = placement.landmark
                Annotation("", coordinate: landmark.coordinate, anchor: placement.anchor) {
                    Button {
                        sheet = .place(landmark)
                        focus(on: landmark.coordinate)
                    } label: {
                        LandmarkMarker(landmark: landmark, isSaved: viewModel.mapSavedIDs.contains(landmark.id), isSelected: activeLandmarkID == landmark.id, labelOnLeft: placement.labelOnLeft, showsTitle: placement.showsTitle, isDot: placement.isDot)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(landmark.title + (viewModel.mapSavedIDs.contains(landmark.id) ? ", saved" : ""))
                    .accessibilityIdentifier("place-\(landmark.id)")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        // No compass: rotate gestures are off, and the walk's heading-up view turns north-up when it
        // closes. MapKit's default compass also sat under the status bar.
        .mapControls { }
        .environment(\.colorScheme, .dark)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleCenter = context.region.center
            visibleRegion = context.region
            cameraDistance = context.camera.distance
            cameraHeading = context.camera.heading
            hasMoved = TourViewModel.distance(visibleCenter, viewModel.searchCenter) > 500
                && fittedCenter.map { TourViewModel.distance(visibleCenter, $0) > 500 } ?? true
        }
        .ignoresSafeArea()
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { viewport = geometry.size }
                    .onChange(of: geometry.size) { _, size in viewport = size }
            }
        }
        .overlay(alignment: .top) { mapControls.padding(.horizontal, 16).padding(.top, 8) }
        .overlay(alignment: .bottom) {
            if sheet == nil && showsBottomPanel {
                GeometryReader { geometry in
                    bottomPanel
                        .padding(.bottom, max(bottomInset, geometry.safeAreaInsets.bottom))
                        .background(TourStyle.paper, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("mapBottomPanel")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .overlay(alignment: .bottom) {
            if let selected = sheet {
                EdgeToEdgeSheet(initialFraction: ["walk", "walks"].contains(selected.id) ? 0.62 : 0.52,
                                allowsCollapsed: selected.id == "walk", onClose: closeSheet) {
                    switch selected {
                    case .place(let landmark):
                        LandmarkDetailView(landmark: landmark, viewModel: viewModel, onClose: { sheet = nil })
                    case .saved:
                        TourListView(viewModel: viewModel, showPlace: { sheet = .place($0) }, startWalk: startWalk, onClose: { sheet = nil })
                    case .walks:
                        SavedWalksView(viewModel: viewModel, openWalk: { walk in
                            viewModel.openSavedWalk(walk)
                            startWalk()
                        }, editDraft: {
                            viewModel.returnToDraft()
                            sheet = .saved
                        }, onClose: closeSheet)
                    case .walk:
                        WalkingTourView(viewModel: viewModel, onClear: {
                            viewModel.clearCurrentRoute()
                            sheet = nil
                        }, onSave: {
                            viewModel.toggleCurrentWalkSaved()
                        })
                    }
                }
                .id(selected.id)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: sheet?.id)
        .onChange(of: viewModel.cameraRevision) { _, _ in
            fittedCenter = nil
            if case .place(let landmark) = sheet { focus(on: landmark.coordinate) }
            else { setRegion(center: viewModel.searchCenter, span: 0.024) }
        }
        .onChange(of: viewModel.routeFitRevision) { _, _ in fitTour() }
        .onChange(of: viewModel.currentStopIndex) { _, _ in
            if sheet?.id == "walk" { showCurrentStop() }
        }
        .onChange(of: sheet?.id) { previous, current in
            // Leaving the walk turns the map back to north-up where it is.
            guard previous == "walk", current == nil, abs(cameraHeading) > 0.5 else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                position = .camera(MapCamera(centerCoordinate: visibleCenter, distance: cameraDistance, heading: 0, pitch: 0))
            }
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--preview"),
                  ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            if ProcessInfo.processInfo.arguments.contains("--detail") {
                sheet = .place(Landmark.previews[0])
            }
        }
        #endif
    }

    private var mapControls: some View {
        HStack(alignment: .top) {
            if hasMoved && !viewModel.isBusy && sheet == nil {
                Button {
                    viewModel.search(near: visibleCenter)
                    hasMoved = false
                    fittedCenter = nil
                } label: {
                    Label("Search this area", systemImage: "magnifyingglass")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent).tint(TourStyle.paper).foregroundStyle(TourStyle.ink)
                .clipShape(Capsule())
            }
            Spacer()
            VStack(spacing: 11) {
                Button { sheet = .walks } label: {
                    Image("WalkHeartMap").renderingMode(.original)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .frame(width: 44, height: 44)
                }
                    .accessibilityLabel("Saved walks, \(viewModel.savedWalks.count)")
                    .accessibilityIdentifier("savedWalks")
                Button {
                    if let location = viewModel.userLocation { setRegion(center: location, span: 0.018) }
                    else { viewModel.locate() }
                } label: {
                    Image("NearMe").renderingMode(.original)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                    .accessibilityLabel("Find my location")
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.8), radius: 2)
        }
        .environment(\.colorScheme, .light)
    }

    /// The landmark drawn with the large pin: the open place card, or the current stop while walking.
    private var activeLandmarkID: String? {
        switch sheet {
        case .place(let landmark): landmark.id
        case .walk: viewModel.currentStop?.id
        default: nil
        }
    }

    private var showsBottomPanel: Bool {
        viewModel.error != nil || viewModel.isBusy || !viewModel.savedLandmarks.isEmpty || viewModel.landmarks.isEmpty
    }

    @ViewBuilder private var bottomPanel: some View {
        if let error = viewModel.error {
            VStack(alignment: .leading, spacing: 10) {
                Text(error).font(.subheadline)
                HStack {
                    Button("Search this area") { viewModel.search(near: visibleCenter) }
                    Spacer()
                    if viewModel.authorizationStatus == .denied {
                        Link("Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    } else {
                        Button("Retry") { viewModel.locate() }
                    }
                }.font(.subheadline.bold())
            }
            .padding(20).frame(maxWidth: .infinity).background(TourStyle.paper)
            .foregroundStyle(TourStyle.ink)
        } else if viewModel.isBusy {
            HStack(spacing: 12) {
                ProgressView().tint(TourStyle.ink)
                Text(viewModel.statusMessage).font(.subheadline)
                Spacer()
            }.padding(20).background(TourStyle.paper).foregroundStyle(TourStyle.ink)
        } else if !viewModel.savedLandmarks.isEmpty {
            WalkSummaryHeader(viewModel: viewModel, onOpen: {
                if viewModel.routeStops.isEmpty { sheet = .saved }
                else { startWalk() }
            }, onSave: {
                viewModel.toggleCurrentWalkSaved()
            }, onAction: {
                viewModel.clearCurrentRoute()
            })
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(TourStyle.ink)
            .environment(\.colorScheme, .light)
        } else if viewModel.landmarks.isEmpty {
            VStack(spacing: 8) {
                Text("A little curiosity goes a long way.").font(.headline)
                Text(viewModel.statusMessage).font(.subheadline)
                Button("Search this area") { viewModel.search(near: visibleCenter) }.font(.subheadline.bold())
            }.padding(20).frame(maxWidth: .infinity).background(TourStyle.paper).foregroundStyle(TourStyle.ink)
        }
    }

    private var placedLandmarks: [PlacedLandmark] {
        LandmarkMapLayout.place(viewModel.mapLandmarks, savedIDs: viewModel.mapSavedIDs,
                                selectedID: activeLandmarkID, region: visibleRegion, viewport: viewport,
                                excludedRects: [CGRect(x: viewport.width - 80, y: 0, width: 80, height: 190)],
                                camera: (cameraHeading, cameraDistance * Self.visibleHeightPerDistance / max(1, viewport.height)))
            .sorted { $0.isDot && !$1.isDot } // Render full markers above dots.
    }

    private func closeSheet() {
        sheet = nil
        viewModel.returnToDraft()
    }

    private func startWalk() {
        viewModel.currentStopIndex = 0
        sheet = .walk
        showCurrentStop()
    }

    /// Zooms to show the user, every stop of a suggested tour, and its route once it loads: in for a
    /// compact walk through a dense city center, out for a drive across the countryside.
    private func fitTour() {
        let roadPoints = viewModel.routeLines.flatMap { line in
            (0..<line.pointCount).map { line.points()[$0].coordinate }
        }
        let coordinates = viewModel.savedLandmarks.map(\.coordinate) + roadPoints
            + [viewModel.userLocation].compactMap { $0 }
        guard let first = coordinates.first else { return }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
        }
        // Extra room below keeps the southernmost stop clear of the tour bar.
        let latitudeDelta = max(0.006, (maxLat - minLat) * 1.5)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latitudeDelta * 0.06,
                                            longitude: (minLon + maxLon) / 2)
        fittedCenter = center
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
            position = .region(MKCoordinateRegion(center: center, span: .init(latitudeDelta: latitudeDelta,
                                                                            longitudeDelta: max(0.0045, (maxLon - minLon) * 1.4))))
        }
    }

    /// MapKit shows a flat map about 0.535 times as tall, in meters, as the camera's distance.
    private static let visibleHeightPerDistance = 0.535
    /// Street level: about 780 m of map height, close enough that cross-street names show.
    private static let streetLevelDistance = 780 / visibleHeightPerDistance

    /// Turns the map toward the current stop, like heading-up navigation: the heading runs from the
    /// previous stop (or the user, for the first stop) to this one. Zooms in to street level unless
    /// the user is already closer, and keeps the stop above the walk sheet.
    private func showCurrentStop() {
        guard let stop = viewModel.currentStop else { return }
        let index = viewModel.currentStopIndex
        let stops = viewModel.routeStops
        let previous = index > 0 ? stops[index - 1].coordinate : viewModel.userLocation
        var heading = 0.0
        if let previous, TourViewModel.distance(previous, stop.coordinate) > 20 {
            heading = Self.bearing(from: previous, to: stop.coordinate)
        } else if stops.indices.contains(index + 1) {
            heading = Self.bearing(from: stop.coordinate, to: stops[index + 1].coordinate)
        }
        let distance = min(cameraDistance, Self.streetLevelDistance)
        // A quarter of the visible height toward the bottom of the rotated screen.
        let center = Self.coordinate(from: stop.coordinate, bearing: heading + 180,
                                     meters: distance * Self.visibleHeightPerDistance * 0.25)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            position = .camera(MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: 0))
        }
    }

    /// Initial compass bearing in degrees from one coordinate to another.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `meters` away along a compass bearing; accurate at walking distances.
    static func coordinate(from origin: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let north = meters * cos(radians), east = meters * sin(radians)
        return CLLocationCoordinate2D(latitude: origin.latitude + north / 111_320,
                                      longitude: origin.longitude + east / (111_320 * cos(origin.latitude * .pi / 180)))
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        // Keep the zoom the user chose, and keep the landmark above the reading sheet by placing it
        // a quarter of the visible height above the map's center.
        let span = visibleRegion.span
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - span.latitudeDelta * 0.25,
                                            longitude: coordinate.longitude)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func setRegion(center: CLLocationCoordinate2D, span: Double) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            position = .region(MKCoordinateRegion(center: center, span: .init(latitudeDelta: span, longitudeDelta: span * 0.75)))
        }
    }
}

struct LandmarkMarker: View {
    let landmark: Landmark
    let isSaved: Bool
    let isSelected: Bool
    var labelOnLeft = false
    var showsTitle = true
    var isDot = false
    @ScaledMetric(relativeTo: .caption) private var labelSize = 14
    @ScaledMetric(relativeTo: .body) private var activeLabelSize = 16

    var body: some View {
        Group {
            if isDot {
                // Original 10pt dot plus the export's shadow, centered on its coordinate.
                Image("HiddenLandmark").renderingMode(.original)
                    .offset(y: 2)
                    .frame(width: 24, height: 24)
            } else if isSelected {
                HStack(alignment: .top, spacing: 6) {
                    if showsTitle && labelOnLeft { title.padding(.top, 12) }
                    ZStack(alignment: .top) {
                        Image("ActiveMarker").renderingMode(.original)
                            .frame(width: 60, height: 68).offset(y: 0.234)
                        // The bundled emoji uses a 120pt glyph in a 144pt canvas.
                        LandmarkEmoji(landmark: landmark, size: 32 * 144 / 120)
                            .frame(width: 32, height: 38).padding(.top, 14)
                        Image("ActiveLandmarkDot").renderingMode(.original)
                            .frame(width: 10, height: 10).offset(y: 69)
                    }
                    .frame(width: 60, height: 77, alignment: .top)
                    if showsTitle && !labelOnLeft { title.padding(.top, 12) }
                }
            } else {
                HStack(spacing: 6) {
                    if showsTitle && labelOnLeft { title }
                    LandmarkEmoji(landmark: landmark, size: 24)
                        .frame(width: 40, height: 40)
                        // The drop shadow belongs to the circle only. Shadowing the whole marker made the
                        // emoji cast a shadow onto the fill, which read as an inner shadow.
                        .background(Circle().fill(isSaved ? TourStyle.savedMarkerFill : .white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 2))
                        .overlay(Circle().strokeBorder(isSaved ? TourStyle.accent : .clear, lineWidth: 2))
                    if showsTitle && !labelOnLeft { title }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityValue(isSelected ? "Selected landmark" : isSaved ? "Saved landmark" : "Landmark")
    }

    private var title: some View {
        Text(landmark.title)
            .font(.system(size: isSelected ? activeLabelSize : labelSize, weight: .bold, design: .rounded))
            .tracking(isSelected ? 0.16 : 0.14)
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 3)
            .multilineTextAlignment(labelOnLeft ? .trailing : .leading)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(width: isSelected ? 122 : 115, alignment: labelOnLeft ? .trailing : .leading)
    }
}

struct PlacedLandmark: Identifiable {
    let landmark: Landmark
    let labelOnLeft: Bool
    let showsTitle: Bool
    let bounds: CGRect
    let markerSize: CGFloat
    var id: String { landmark.id }
    var isDot: Bool { markerSize == 10 }
    var anchor: UnitPoint {
        if markerSize == 60 {
            guard showsTitle else { return UnitPoint(x: 0.5, y: 72.0 / 77.0) }
            let fraction = 30.0 / 188.0
            return UnitPoint(x: labelOnLeft ? 1 - fraction : fraction, y: 72.0 / 77.0)
        }
        guard showsTitle else { return .center }
        let fraction = (markerSize / 2) / (markerSize + 121)
        return UnitPoint(x: labelOnLeft ? 1 - fraction : fraction, y: 0.5)
    }
}

/// Reserve screen space for labels as the map zoom changes. Nearby places that
/// cannot fit a label keep an emoji marker; hidden unsaved markers become small dots.
enum LandmarkMapLayout {
    /// `camera` describes a rotated map: its heading and meters per screen point. A rotated map's
    /// region is only the bounding box of the screen, so it cannot be used to project points.
    static func place(_ landmarks: [Landmark], savedIDs: Set<String>, selectedID: String?,
                      region: MKCoordinateRegion, viewport: CGSize, excludedRects: [CGRect] = [],
                      camera: (heading: Double, metersPerPoint: Double)? = nil) -> [PlacedLandmark] {
        guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return [] }
        func project(_ landmark: Landmark) -> CGPoint {
            if let camera, abs(camera.heading) > 0.5, camera.metersPerPoint > 0 {
                let east = (landmark.longitude - region.center.longitude) * 111_320 * cos(region.center.latitude * .pi / 180)
                let north = (landmark.latitude - region.center.latitude) * 111_320
                let heading = camera.heading * .pi / 180
                let right = east * cos(heading) - north * sin(heading)
                let up = east * sin(heading) + north * cos(heading)
                return CGPoint(x: viewport.width / 2 + right / camera.metersPerPoint,
                               y: viewport.height / 2 - up / camera.metersPerPoint)
            }
            return CGPoint(x: (0.5 + (landmark.longitude - region.center.longitude) / region.span.longitudeDelta) * viewport.width,
                           y: (0.5 - (landmark.latitude - region.center.latitude) / region.span.latitudeDelta) * viewport.height)
        }
        let ordered = landmarks.sorted { a, b in
            let pa = a.id == selectedID ? 2 : savedIDs.contains(a.id) ? 1 : 0
            let pb = b.id == selectedID ? 2 : savedIDs.contains(b.id) ? 1 : 0
            if pa != pb { return pa > pb }
            let da = pow(a.latitude - region.center.latitude, 2) + pow(a.longitude - region.center.longitude, 2)
            let db = pow(b.latitude - region.center.latitude, 2) + pow(b.longitude - region.center.longitude, 2)
            return da == db ? a.id < b.id : da < db
        }
        var placed: [PlacedLandmark] = []
        var dots: [PlacedLandmark] = []
        let canvas = CGRect(origin: .zero, size: viewport)
        // Reserve every saved stop before placing any labels. Even two saved
        // stops at the same coordinate must remain available as map annotations.
        let protectedMarkers: [(id: String, bounds: CGRect)] = ordered.compactMap { landmark in
            guard savedIDs.contains(landmark.id) || landmark.id == selectedID else { return nil }
            let point = project(landmark)
            let x = point.x, y = point.y
            let bounds = landmark.id == selectedID
                ? CGRect(x: x - 30, y: y - 72, width: 60, height: 77)
                : CGRect(x: x - 20, y: y - 20, width: 40, height: 40)
            return (landmark.id, bounds)
        }
        for landmark in ordered {
            let point = project(landmark)
            let x = point.x, y = point.y
            guard canvas.insetBy(dx: -20, dy: -20).contains(CGPoint(x: x, y: y)) else { continue }
            if landmark.id == selectedID {
                let marker = CGRect(x: x - 30, y: y - 72, width: 60, height: 77)
                var selection = PlacedLandmark(landmark: landmark, labelOnLeft: false, showsTitle: false, bounds: marker, markerSize: 60)
                for left in [false, true] {
                    let bounds = CGRect(x: left ? marker.minX - 128 : marker.minX,
                                        y: marker.minY, width: 188, height: 77)
                    if canvas.contains(bounds),
                       !excludedRects.contains(where: { $0.intersects(bounds) }),
                       !protectedMarkers.contains(where: { $0.id != landmark.id && $0.bounds.insetBy(dx: -6, dy: -6).intersects(bounds) }) {
                        selection = PlacedLandmark(landmark: landmark, labelOnLeft: left, showsTitle: true, bounds: bounds, markerSize: 60)
                        break
                    }
                }
                placed.append(selection)
                continue
            }
            let size: CGFloat = 40
            let marker = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
            var choice: PlacedLandmark?
            for left in [x > viewport.width / 2, x <= viewport.width / 2] {
                let bounds = CGRect(x: left ? marker.minX - 121 : marker.minX, y: marker.minY - 3,
                                    width: size + 121, height: size + 6)
                if canvas.contains(bounds),
                   !protectedMarkers.contains(where: { $0.id != landmark.id && $0.bounds.insetBy(dx: -6, dy: -6).intersects(bounds) }),
                   !excludedRects.contains(where: { $0.intersects(bounds) }), !placed.contains(where: { $0.bounds.insetBy(dx: -6, dy: -6).intersects(bounds) }) {
                    choice = PlacedLandmark(landmark: landmark, labelOnLeft: left, showsTitle: true, bounds: bounds, markerSize: size)
                    break
                }
            }
            if let choice { placed.append(choice) }
            else if savedIDs.contains(landmark.id) || (
                !excludedRects.contains(where: { $0.intersects(marker) }) &&
                !protectedMarkers.contains(where: { $0.bounds.insetBy(dx: -6, dy: -6).intersects(marker) }) &&
                !placed.contains(where: { $0.bounds.insetBy(dx: -6, dy: -6).intersects(marker) })) {
                placed.append(PlacedLandmark(landmark: landmark, labelOnLeft: false, showsTitle: false, bounds: marker, markerSize: size))
            } else {
                dots.append(PlacedLandmark(landmark: landmark, labelOnLeft: false, showsTitle: false,
                                           bounds: CGRect(x: x - 5, y: y - 5, width: 10, height: 10), markerSize: 10))
            }
        }
        // Dots do not reserve room that would otherwise fit a full landmark marker.
        return placed + dots
    }
}
