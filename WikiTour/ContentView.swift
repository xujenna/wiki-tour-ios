import SwiftUI

struct ContentView: View {
    @State private var viewModel = TourViewModel()

    var body: some View {
        Group {
            switch viewModel.authorizationStatus {
            case .denied, .restricted:
                LocationDeniedView()

            default:
                if viewModel.phase == .idle ||
                   viewModel.phase == .locating ||
                   viewModel.phase == .geocoding ||
                   (viewModel.phase == .loading && viewModel.landmarks.isEmpty) {
                    LoadingView(viewModel: viewModel)
                } else {
                    TabView {
                        NavigationStack {
                            TourMapView(viewModel: viewModel)
                                .navigationDestination(for: Landmark.self) { landmark in
                                    LandmarkDetailView(landmark: landmark)
                                }
                        }
                        .tabItem { Label("Map", systemImage: "map.fill") }

                        NavigationStack {
                            TourListView(viewModel: viewModel)
                                .navigationDestination(for: Landmark.self) { landmark in
                                    LandmarkDetailView(landmark: landmark)
                                }
                        }
                        .tabItem { Label("Tour", systemImage: "figure.walk") }
                    }
                }
            }
        }
        .onAppear { viewModel.start() }
    }
}

// MARK: - Loading screen (mirrors the "Finding historical landmarks…" state in the original)

struct LoadingView: View {
    let viewModel: TourViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "building.columns")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("WikiTour")
                .font(.largeTitle.bold())

            if let error = viewModel.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .animation(.default, value: viewModel.statusMessage)
                }
            }
        }
        .padding(40)
    }
}

// MARK: - Location denied

struct LocationDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Location Access Required")
                .font(.title2.bold())

            Text("WikiTour needs your location to find nearby historical landmarks on the National Register of Historic Places.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
    }
}
