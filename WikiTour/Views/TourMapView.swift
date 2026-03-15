import SwiftUI
import MapKit

struct TourMapView: View {
    let viewModel: TourViewModel

    @State private var selectedLandmark: Landmark?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: $selectedLandmark) {
                UserAnnotation()

                // Straight-line walking route connecting the stops (mirrors Google Maps
                // walking directions in the original).
                if viewModel.routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: viewModel.routeCoordinates)
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 3)
                }

                // Numbered stop markers.
                ForEach(viewModel.landmarks) { landmark in
                    Annotation(landmark.title, coordinate: landmark.coordinate, anchor: .bottom) {
                        StopMarker(
                            number: landmark.stopNumber ?? 0,
                            isSelected: selectedLandmark == landmark
                        )
                        .onTapGesture { selectedLandmark = landmark }
                    }
                    .tag(landmark)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()

            // Floating header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.locationName.isEmpty ? "WikiTour" : viewModel.locationName)
                        .font(.title3.bold())
                    if !viewModel.landmarks.isEmpty {
                        Text("\(viewModel.landmarks.count)-stop walking tour")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.phase == .loading {
                    ProgressView()
                } else {
                    Button { viewModel.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        // Bottom card for tapped landmark
        .safeAreaInset(edge: .bottom) {
            if let landmark = selectedLandmark {
                NavigationLink(value: landmark) {
                    LandmarkCard(landmark: landmark)
                }
                .buttonStyle(.plain)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: selectedLandmark)
        .navigationBarHidden(true)
    }
}

// MARK: - Numbered stop marker (mirrors Google Maps numbered labels in the original)

struct StopMarker: View {
    let number: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .white)
                .frame(width: isSelected ? 40 : 30, height: isSelected ? 40 : 30)
                .shadow(color: .black.opacity(0.2), radius: 4)
            Text("\(number)")
                .font(.system(size: isSelected ? 16 : 12, weight: .bold))
                .foregroundStyle(isSelected ? .white : Color.accentColor)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Bottom card for selected landmark

struct LandmarkCard: View {
    let landmark: Landmark

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text("\(landmark.stopNumber ?? 0)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(landmark.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if !landmark.formattedDistance.isEmpty {
                    Label(landmark.formattedDistance + " away", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
