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
                ForEach(viewModel.landmarks) { landmark in
                    Annotation(landmark.title, coordinate: landmark.coordinate, anchor: .bottom) {
                        LandmarkMarker(isSelected: selectedLandmark == landmark)
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
                    Text("WikiTour")
                        .font(.title3.bold())
                    if !viewModel.landmarks.isEmpty {
                        Text("\(viewModel.landmarks.count) landmarks nearby")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.isLoading {
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
        // Bottom card for the tapped landmark
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

// MARK: - Sub-views

struct LandmarkMarker: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .white)
                .frame(width: isSelected ? 42 : 30, height: isSelected ? 42 : 30)
                .shadow(color: .black.opacity(0.2), radius: 4)
            Image(systemName: "building.columns.fill")
                .font(.system(size: isSelected ? 18 : 13))
                .foregroundStyle(isSelected ? .white : Color.accentColor)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct LandmarkCard: View {
    let landmark: Landmark

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.columns.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

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
