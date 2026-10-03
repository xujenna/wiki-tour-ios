import SwiftUI

struct LandmarkDetailView: View {
    let landmark: Landmark
    let viewModel: TourViewModel
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LandmarkPhoto(landmark: landmark)
                    .frame(height: 226)
                    .overlay(alignment: .bottomLeading) {
                        Text(landmark.title)
                            .font(.system(size: 30, weight: .bold, design: .rounded)).tracking(0.3)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 10)
                            .padding(.horizontal, 20).padding(.bottom, 10)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { viewModel.toggleSaved(landmark) } label: {
                            Image(viewModel.isSaved(landmark) ? "BookmarkFilled" : "Bookmark")
                                .renderingMode(.template)
                                .foregroundStyle(viewModel.isSaved(landmark) ? Color.accentColor : TourStyle.ink)
                                .frame(width: 40, height: 40)
                                .background(.white, in: Circle())
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(viewModel.isSaved(landmark) ? "Remove saved place" : "Save place")
                        .accessibilityIdentifier("bookmarkPlace")
                        .padding(10)
                    }
                VStack(alignment: .leading, spacing: 10) {
                    if !landmark.formattedDistance.isEmpty {
                        Text(landmark.formattedDistance + " away")
                            .font(.system(size: 14, weight: .semibold, design: .rounded)).tracking(0.14)
                    }
                    LandmarkDescription(landmark: landmark, viewModel: viewModel)
                    if let url = landmark.wikipediaURL {
                        Link("Read more on Wikipedia", destination: url)
                            .font(.system(size: 14, weight: .semibold, design: .rounded)).tracking(0.14)
                            .foregroundStyle(TourStyle.ink)
                            .padding(.vertical, 8)
                    }
                }
                .padding(20)
            }
        }
        .background(TourStyle.paper)
        .foregroundStyle(TourStyle.ink)
        .environment(\.colorScheme, .light)
        .accessibilityAction(.escape, onClose)
    }
}

struct LandmarkPhoto: View {
    let landmark: Landmark
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let asset = landmark.previewImage {
                    Image(asset).resizable().scaledToFill()
                } else if let url = landmark.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .empty: placeholder.overlay { ProgressView().tint(.white) }
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom))
        }
        .accessibilityLabel(landmark.imageURL == nil && landmark.previewImage == nil ? landmark.title : "Photo of \(landmark.title)")
    }

    private var placeholder: some View {
        ZStack {
            Color(red: 0.27, green: 0.32, blue: 0.38)
            LandmarkEmoji(landmark: landmark, size: 52)
        }
    }
}

/// Bundled renders of the native Apple emoji keep markers readable even when
/// an iOS Simulator runtime lacks its downloadable color-emoji font.
struct LandmarkEmoji: View {
    let landmark: Landmark
    var size: CGFloat = 24
    var body: some View {
        Image(landmark.emojiAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Both map cards and tour stops share the same on-demand introduction and session cache.
struct LandmarkDescription: View {
    let landmark: Landmark
    let viewModel: TourViewModel
    @State private var isLoading = false
    @State private var failed = false
    @State private var retry = 0

    private var paragraphs: [String] {
        // Designated places arrive without a summary; show only the loading state until it arrives.
        if viewModel.articleDescriptions[landmark.id] == nil, landmark.description.isEmpty, !failed { return [] }
        let text = viewModel.articleDescriptions[landmark.id] ?? (landmark.description.isEmpty
            ? "Open Wikipedia to learn more about this place." : landmark.description)
        return text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            // One body style for place cards and walk stops (Figma 4:72 and 4:181).
            .font(.system(size: 18, design: .rounded)).tracking(0.18).lineSpacing(3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("landmarkDescription")
            if isLoading {
                ProgressView("Loading more about this place…").font(.caption)
            } else if failed {
                Button("Retry loading introduction") { retry += 1 }.font(.caption)
            }
        }
        .task(id: "\(landmark.id)-\(retry)") {
            failed = false
            isLoading = true
            defer { isLoading = false }
            do { try await viewModel.loadDescription(for: landmark) }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}
