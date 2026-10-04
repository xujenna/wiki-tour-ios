import SwiftUI
import MapKit

struct TourListView: View {
    let viewModel: TourViewModel
    let showPlace: (Landmark) -> Void
    let startWalk: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.savedLandmarks.isEmpty {
                    EmptyStateView(title: "A walk of your own", systemImage: "bookmark",
                                   message: "Tap a place on the map, then bookmark it. Your saved places become your walking tour.")
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(viewModel.savedLandmarks) { landmark in
                            Button { showPlace(landmark) } label: {
                                HStack(spacing: 12) {
                                    LandmarkEmoji(landmark: landmark, size: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(landmark.title).font(.brandon(17, bold: true, relativeTo: .headline))
                                        if !landmark.formattedDistance.isEmpty {
                                            Text(landmark.formattedDistance + " away").font(.brandon(12, relativeTo: .caption))
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                                .foregroundStyle(TourStyle.ink).padding(.vertical, 6)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) { viewModel.toggleSaved(landmark) }
                            }
                        }
                    } footer: {
                        Text("Stops are ordered for a shorter walk. Swipe a place to remove it.")
                    }
                    Section {
                        if viewModel.isRouting {
                            HStack { ProgressView(); Text("Finding directions…") }
                        } else if let error = viewModel.routeError {
                            Text(error)
                            Button("Try directions again") { viewModel.prepareRoute() }
                        } else {
                            Text(viewModel.routeSummary).font(.brandon(15, bold: true, relativeTo: .subheadline))
                            if viewModel.userLocation == nil {
                                Text("This walk starts at your first saved place. Enable location to include the walk from where you are.")
                                    .font(.brandon(12, relativeTo: .caption))
                            }
                            Button(action: startWalk) {
                                Label("Start walking", systemImage: "figure.walk")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(TourStyle.ink)
                            .disabled(viewModel.routeStops.isEmpty)
                            .accessibilityIdentifier("startWalking")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TourStyle.paper)
            .navigationTitle("Saved places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }.foregroundStyle(TourStyle.ink)
                }
            }
        }
        .environment(\.colorScheme, .light)
    }
}

struct WalkingTourView: View {
    @Environment(\.isTourSheetCollapsed) private var isCollapsed
    let viewModel: TourViewModel
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WalkSummaryHeader(viewModel: viewModel, onSave: onSave, onAction: onClear)
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 8)

            if !isCollapsed, let stop = viewModel.currentStop {
                ScrollView {
                    // Figma 25:397: photo 15 pt under the summary, the stop's name 15 pt under the
                    // photo, and the description 10 pt under the name.
                    VStack(alignment: .leading, spacing: 10) {
                        LandmarkPhoto(landmark: stop).frame(height: 204)
                            .padding(.top, 7)
                        // 24 pt on a 22 pt line, tighter than Brandon's own leading.
                        MockText(text: stop.title, font: BundledFonts.displayBlack, size: 24, lineHeight: 22,
                                 identifier: "currentStopTitle")
                            .padding(.top, 5)
                        LandmarkDescription(landmark: stop, viewModel: viewModel, compact: true)
                        HStack {
                            if let url = stop.wikipediaURL {
                                Link("Wikipedia", destination: url)
                            }
                            Spacer()
                            Button("Directions") { openDirections(to: stop) }
                        }.font(.brandon(12, bold: true, relativeTo: .caption)).padding(.top, 8)
                    }.padding(.horizontal, 20).padding(.bottom, 12)
                }
                .id(stop.id)
                if let message = viewModel.extendMessage, isLastStop {
                    Text(message).mockFont(BundledFonts.textRegular, size: 14, lineHeight: 20)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 20)
                }
                HStack {
                    let isFirstStop = viewModel.currentStopIndex == 0
                    Button("← BACK") { viewModel.currentStopIndex -= 1 }
                        .disabled(isFirstStop)
                        // The sheet's ink color overrides the system's dimmed disabled style.
                        .opacity(isFirstStop ? 0.3 : 1)
                    Spacer()
                    if viewModel.isExtending {
                        HStack(spacing: 8) { ProgressView(); Text("FINDING MORE…") }
                    } else {
                        Button(nextLabel) {
                            if !isLastStop { viewModel.currentStopIndex += 1 }
                            else if viewModel.canKeepGoing { viewModel.keepGoing() }
                            else { onClear() }
                        }
                        .accessibilityIdentifier("nextStop")
                        .accessibilityValue("Stop \(viewModel.currentStopIndex + 1) of \(viewModel.routeStops.count)")
                    }
                }
                .mockFont(BundledFonts.displayBlack, size: 16, lineHeight: 22)
                .padding(.horizontal, 20).padding(.vertical, 12)
            } else if !isCollapsed {
                EmptyStateView(title: "Choose your stops", systemImage: "bookmark", message: "Save places on the map to make a walking tour.")
            }
        }
        .foregroundStyle(TourStyle.ink)
        .tint(TourStyle.ink)
        .animation(nil, value: isCollapsed)
        .background(TourStyle.paper)
        .environment(\.colorScheme, .light)
    }

    private var isLastStop: Bool { viewModel.currentStopIndex + 1 >= viewModel.routeStops.count }

    /// The last stop of the current tour offers "Keep going"; a saved walk still ends with Finish.
    private var nextLabel: String {
        !isLastStop ? "NEXT →" : viewModel.canKeepGoing ? "KEEP GOING →" : "FINISH ✓"
    }

    private func openDirections(to landmark: Landmark) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: landmark.coordinate))
        item.name = landmark.title
        let mode = viewModel.travelMode == .driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
}

struct SavedWalksView: View {
    let viewModel: TourViewModel
    let openWalk: (SavedWalk) -> Void
    let editDraft: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(viewModel.savedWalks.count) saved \(viewModel.savedWalks.count == 1 ? "walk" : "walks")")
                    .mockFont(BundledFonts.textBold, size: 14)
                Spacer()
                Button("Done", action: onClose).font(.brandon(15, bold: true, relativeTo: .subheadline))
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 16)
            ScrollView {
                LazyVStack(spacing: 20) {
                    if viewModel.savedWalks.isEmpty {
                        EmptyStateView(title: "Your walks belong here", systemImage: "heart",
                                       message: "Bookmark places to build a walk, then tap the heart on your walking tour to save it.")
                    }
                    ForEach(viewModel.savedWalks) { walk in
                        Button { openWalk(walk) } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let cover = walk.cover { LandmarkPhoto(landmark: cover) }
                                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                Text(walk.name)
                                    .mockFont(BundledFonts.displayBlack, size: 32)
                                    .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 10)
                                    .padding(10)
                            }
                            .frame(height: 204).clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(walk.name), \(walk.stops.count) stops")
                        .accessibilityIdentifier("savedWalk-\(walk.id)")
                    }

                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
                    Button(action: editDraft) {
                        Label("Current walk · \(viewModel.savedLandmarks.count) places", systemImage: "bookmark")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("savedPlaces")
        }
        .foregroundStyle(TourStyle.ink).tint(TourStyle.ink)
        .background(TourStyle.paper).environment(\.colorScheme, .light)
    }
}

/// Shared by the collapsed map bar and open walk drawer.
struct WalkSummaryHeader: View {
    let viewModel: TourViewModel
    var onOpen: (() -> Void)? = nil
    let onSave: () -> Void
    let onAction: () -> Void

    private var summary: String {
        viewModel.activeSavedWalk.map { $0.name + " • " + viewModel.routeSummary } ?? viewModel.routeSummary
    }

    var body: some View {
        HStack(spacing: 0) {
            if let onOpen {
                Button(action: onOpen) {
                    summaryText.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Open walking tour. " + summary)
                .accessibilityIdentifier("tourSummary")
            } else {
                summaryText.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Button(action: onSave) {
                Image(viewModel.activeSavedWalk == nil ? "WalkHeart" : "WalkHeartFilled")
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(viewModel.activeSavedWalk == nil ? "Save walk" : "Unsave walk")
            .accessibilityIdentifier("saveWalk")
            .disabled(viewModel.routeStops.isEmpty || viewModel.isRouting)
            Button(action: onAction) {
                Image("WalkDone")
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel("Clear current route")
            .accessibilityIdentifier("walkAction")
        }
        .buttonStyle(.plain)
        .foregroundStyle(TourStyle.ink)
    }

    private var summaryText: some View {
        Text(summary).mockFont(BundledFonts.textBold, size: 14)
            .lineLimit(2).minimumScaleFactor(0.85)
            .padding(.leading, 10).padding(.trailing, 4)
    }
}
