import SwiftUI

struct ContentView: View {
    @State private var viewModel = TourViewModel()

    var body: some View {
        Group {
            if viewModel.authorizationStatus == .denied ||
               viewModel.authorizationStatus == .restricted {
                LocationDeniedView()
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
        .onAppear { viewModel.start() }
    }
}

// MARK: - Location denied placeholder

struct LocationDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Location Access Required")
                .font(.title2.bold())

            Text("WikiTour needs your location to find nearby historical landmarks for your walking tour.")
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
