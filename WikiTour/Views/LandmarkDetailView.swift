import SwiftUI
import MapKit

struct LandmarkDetailView: View {
    let landmark: Landmark

    @State private var summary: String?
    @State private var thumbnailURL: URL?
    @State private var pageURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Hero: photo if available, otherwise a map snippet
                heroImage
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {

                    // Title + distance
                    VStack(alignment: .leading, spacing: 6) {
                        Text(landmark.title)
                            .font(.title2.bold())
                        if !landmark.formattedDistance.isEmpty {
                            Label(landmark.formattedDistance + " from you", systemImage: "location.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Summary / skeleton / error
                    if isLoading {
                        skeletonRows
                    } else if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let summary {
                        Text(summary)
                            .font(.body)
                            .lineSpacing(6)
                    }

                    // Wikipedia link
                    if let pageURL {
                        Divider()
                        Link(destination: pageURL) {
                            Label("Read on Wikipedia", systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }

                    // Directions button
                    Button(action: openInMaps) {
                        Label("Get Walking Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(20)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetails() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var heroImage: some View {
        if let thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    mapSnippet
                default:
                    Rectangle()
                        .fill(.quaternary)
                        .overlay { ProgressView() }
                }
            }
        } else {
            mapSnippet
        }
    }

    private var mapSnippet: some View {
        Map(position: .constant(.region(MKCoordinateRegion(
            center: landmark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))) {
            Marker(landmark.title, coordinate: landmark.coordinate)
        }
        .disabled(true)
    }

    private var skeletonRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(maxWidth: i == 4 ? 200 : .infinity)
                    .frame(height: 14)
            }
        }
    }

    // MARK: - Data loading

    private func loadDetails() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let response = try await WikipediaService.shared.summary(for: landmark.title)
            summary = response.extract
            if let src = response.thumbnail?.source {
                thumbnailURL = URL(string: src)
            }
            if let page = response.contentUrls?.mobile?.page {
                pageURL = URL(string: page)
            }
        } catch {
            loadError = "Could not load details."
        }
    }

    // MARK: - Maps

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: landmark.coordinate))
        item.name = landmark.title
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
