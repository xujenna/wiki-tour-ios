import SwiftUI

struct TourListView: View {
    let viewModel: TourViewModel

    var body: some View {
        List {
            if let error = viewModel.error {
                errorRow(message: error)
            } else if viewModel.landmarks.isEmpty {
                emptyRow
            } else {
                Section {
                    ForEach(viewModel.landmarks) { landmark in
                        NavigationLink(value: landmark) {
                            LandmarkRow(landmark: landmark)
                        }
                    }
                } header: {
                    Text("\(viewModel.landmarks.count)-stop walking tour · \(viewModel.locationName)")
                }
            }
        }
        .navigationTitle("WikiTour")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.phase == .loading {
                    ProgressView()
                } else {
                    Button { viewModel.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Private row helpers

    @ViewBuilder
    private func errorRow(message: String) -> some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { viewModel.refresh() }
                .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var emptyRow: some View {
        ContentUnavailableView(
            "No Landmarks Found",
            systemImage: "building.columns",
            description: Text("No National Register of Historic Places listings were found near your location.")
        )
        .listRowBackground(Color.clear)
    }
}

// MARK: - LandmarkRow

struct LandmarkRow: View {
    let landmark: Landmark

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text("\(landmark.stopNumber ?? 0)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(landmark.title)
                    .font(.body)
                    .lineLimit(2)
                if !landmark.formattedDistance.isEmpty {
                    Label(landmark.formattedDistance, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
