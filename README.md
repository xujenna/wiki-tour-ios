# Walking Tours iOS

A native, map-first walking guide based on the [iOS Figma mocks](https://www.figma.com/design/rFy00JQ033W3LjIo7U1opp/i-guess-we-re-stuck-here?node-id=5-489).

Explore nearby landmarks, open their Wikipedia stories, bookmark interesting places, and take a walk through your saved stops.

## Run

Open `WikiTour.xcodeproj`, choose the **WikiTour** scheme, and run on an iPhone simulator or device. Device builds use team `MR89V3D6JC`. Requires iOS 17+; developed and verified with Xcode 26.3. FirebaseCore 12.19.1 is resolved through Swift Package Manager. The bundled Firebase configuration points only to the dedicated iOS project.

In Simulator, set a location through Features → Location. If location access is unavailable, pan the map and tap **Search this area**. The initial fallback map is Park Slope, Brooklyn; it is not presented as the user's location.

## Experience

- A dark, interactive MapKit map with automatically selected landmark emoji and magenta saved markers.
- Expandable photo/story sheets, bookmark controls, and original Wikipedia links.
- Locally persisted saved places, available across launches and discovery searches.
- Tap the tour heart to save a named walk using the current area. The heart above the map opens a photo-card library. Reopen a walk with its original stop order, Wikipedia summaries, route geometry, distance, and duration; delete it from its detail header. Editing the current walk does not change saved snapshots.
- Walks are stored on-device in `savedWalks.v1`; photo URLs are saved, but downloading photos still requires a connection.
- Walking or driving directions between saved places, ordered to avoid doubling back. Distances, durations, and map polylines come from MapKit; failed requests show a retry state instead of invented directions.
- A walking-tour sheet with Back, Next, and Apple Maps directions for the current stop. The map turns toward the current stop, at street level. On the last stop, **Keep going** adds up to ten more stops from there, using the same rules as a new tour, and only requests directions for the new legs; the check button ends the walk. A reopened saved walk is a fixed snapshot, so its last stop still offers Finish. With no location access, the route starts at the first saved place.
- Loading, empty, denied-location, missing-photo, and network-error states.

## Data and design

Discovery combines two sources. First, Wikidata supplies places with an official heritage designation within 3 km: the National Register of Historic Places, National Historic Landmarks, city landmarks, and equivalent registers abroad. Subway stations, historic districts, and neighborhoods are excluded because they are not single stops. Second, Wikipedia's nearby-article search tops this up with places whose short description names a cultural place type, such as a museum, memorial, church, or park, matched as whole words. Ordinary schools, office buildings, and halls are not included unless they are designated. Either source alone is enough; only a total outage is reported as an error.

As soon as places load, the app suggests a tour and requests directions, as the web app does:

- **Walking:** if at least two places are within an estimated 20-minute walk, the tour takes up to ten places, choosing the nearest next stop each time while the estimated walk stays within 75 minutes. If real walking directions run longer, final stops are dropped until the walk fits. Walks end at the last stop.
- **Driving:** otherwise the app searches the full 6-mile range Wikipedia allows and builds a driving tour of up to ten places within 6 miles, then zooms the map out to show it.
- **Order:** stops are ordered by nearest neighbor and then improved by reversing or moving runs of stops so the route does not cross itself or double back. Designated and other places are treated alike.

Until the first search (and any tour it suggests) is ready, a full-screen loading screen shows a larger version of the app icon: the docbotic.care sky video (`WikiTour/SkyLoop.mp4`, cropped to portrait and re-encoded as HEVC, about 300 KB) loops under a dark halftone, with the icon's shoe centered and a spinner and status caption beneath it. The system launch screen (`WikiTour/Info.plist`) shows the same shoe on the sky's average color so launch hands off without a jump. Regenerate the shoe with `swift scripts/render-loading-shoe.swift WikiTour/Assets.xcassets`.

A new suggested tour opens with a welcome postcard (Figma node 25:486) in place of the tour bar: the first stop's Wikipedia photo, toned with Core Image to match the mock's image adjustments, under a pink halftone, with "Welcome to" the neighborhood and its city (or the city and its state or country). Place names come from OpenStreetMap's reverse geocoder, with Apple's as a fallback, because Apple does not return New York City neighborhoods. Tapping the postcard starts the walk; swiping it down dismisses it. Borel is bundled under the SIL Open Font License (license in `resources/fonts`); Brandon Grotesque and Brandon Text are commercial fonts, so they are git-ignored: run `scripts/install-brandon-fonts.sh` to copy them from this Mac's installed fonts into the asset catalog before building. Without them, that lettering falls back to the system font.

Panning the map keeps the current tour. Tapping **Search this area** asks for a new tour there: it replaces the current draft, even an edited one (saved walks are untouched), shows a new postcard, and starts from the searched spot when the user is more than 1 km away. A new device location replaces the suggestion only while it is untouched. Bookmarking or removing a place turns the suggestion into the user's own draft, which later searches never overwrite or shorten. Clearing the route lets the next search suggest a fresh tour.

Each place's emoji comes from its short description first, then its Wikidata type (for example "church building" or "private mansion"), then its name. Generic words such as house, park, street, or bank count only in a description or type, never in a name, so “Park Avenue” is not a park. The taxonomy covers armories and castles, religious buildings, schools, theaters and concert halls, libraries, cemeteries, parks, gardens, bridges, towers, houses and mansions, fountains, statues, ruins, hotels, restaurants, shops, offices, hospitals, and squares, with 🏛️ as the fallback. Designated places are also excluded by Wikidata type, which catches stations whatever language their description uses. Emoji are bundled renders of the system Apple emoji so missing simulator fonts cannot turn map markers into question marks. Regenerate them on macOS with:

```sh
swift scripts/render-emoji.swift WikiTour/Assets.xcassets
```

Bookmark/close icons and the preview Armory photo are local Figma exports. Production photographs and article extracts load dynamically from Wikipedia; the map and walking route use live MapKit data rather than the static map/route images in the mocks. Bottom sheets span the full screen width and reach the bottom edge, with an accessible drag handle for resizing and dismissal.

## Verification

The shared scheme includes `WikiTourTests` and `WikiTourUITests`. Run Product → Test in Xcode. Tests cover zoom-aware map-label collision handling, Wikipedia filtering/outages, classification, stable bookmark identity/persistence, stop ordering, walking-route metrics and cancellation, route failure, and save/remove/relaunch/Back/Next/Keep going interactions.

The `--ui-testing --preview` launch arguments enable deterministic fixtures and isolated bookmark storage exclusively for UI tests. Normal launches always use live location, Wikipedia content, and MapKit directions. `--detail`, `--saved-preview`, and `--reset-saved` are UI-test helpers.

## Firebase and distribution

The iOS app uses its own Firebase project, [wiki-tour-ios-xujenna](https://console.firebase.google.com/project/wiki-tour-ios-xujenna/overview), separate from the web app's `wiki-tour` project. Bundle ID: `com.xujenna.wikitour`. FirebaseCore initializes on normal launches. Authentication, Firestore sync, analytics, and crash reporting are not enabled in this first build; saved walks remain local.

TestFlight build instructions and status are in `docs/testflight.md`.
