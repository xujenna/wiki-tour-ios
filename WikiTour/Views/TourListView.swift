import SwiftUI

struct TourListView: View {
    let viewModel: TourViewModel

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.landmarks.isEmpty {
                loadingRow
            } else if let error = viewModel.error {
                errorRow(message: error)
            } else if viewModel.landmarks.isEmpty {
                emptyRow
            } else {
                Section {
                    ForEach(Array(viewModel.landmarks.enumerated()), id: \.element.id) { index, landmark in
                        NavigationLink(value: landmark) {
                            LandmarkRow(landmark: landmark, stopNumber: index + 1)
                        }
                    }
                } header: {
                    Text("Walking Tour · \(viewModel.landmarks.count) stops")
                }
            }
        }
        .navigationTitle("WikiTour")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
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
    private var loadingRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                Text("Finding nearby landmarks…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
        .padding(.top, 60)
    }

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
            systemImage: "map.circle",
            description: Text("No historical landmarks found within \(viewModel.searchRadius) m of your location.")
        )
        .listRowBackground(Color.clear)
    }
}

// MARK: - LandmarkRow

struct LandmarkRow: View {
    let landmark: Landmark
    let stopNumber: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text("\(stopNumber)")
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
