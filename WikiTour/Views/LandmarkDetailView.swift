import SwiftUI
import MapKit

struct LandmarkDetailView: View {
    let landmark: Landmark

    @State private var isLoading = false    // summary already in landmark.description
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Hero image or map snippet
                heroImage
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {

                    // Stop number + title
                    VStack(alignment: .leading, spacing: 6) {
                        if let stop = landmark.stopNumber {
                            Text("Stop \(stop)")
                                .font(.caption.uppercaseSmallCaps())
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(landmark.title)
                            .font(.title2.bold())
                        if !landmark.formattedDistance.isEmpty {
                            Label(landmark.formattedDistance + " from you", systemImage: "location.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Description (extract from Wikipedia summary)
                    if landmark.description.isEmpty {
                        Text("No description available.")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Text(landmark.description)
                            .font(.body)
                            .lineSpacing(6)
                    }

                    // Wikipedia link
                    if let pageURL = landmark.wikipediaURL {
                        Divider()
                        Link(destination: pageURL) {
                            Label("Read on Wikipedia", systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }

                    // Walking directions via Apple Maps
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
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var heroImage: some View {
        if let imageURL = landmark.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                case .failure:          mapSnippet
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

    // MARK: - Actions

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: landmark.coordinate))
        item.name = landmark.title
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
