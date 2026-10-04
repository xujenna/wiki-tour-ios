# Walking Tours TestFlight

- Bundle ID: `com.xujenna.wikitour`
- Apple developer team: `MR89V3D6JC`
- Current version: 1.0 (11) — uploaded October 4, 2026; supersedes build 10
- Firebase project: `wiki-tour-ios-xujenna`; iOS app ID `1:607056516365:ios:3e2ad18e46012e2344cc44`
- Saved places and walks persist locally. FirebaseCore is configured; this build does not include authentication or cloud synchronization.

Archive:

```sh
xcodebuild -project WikiTour.xcodeproj -scheme WikiTour -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/WikiTour-TestFlight-v4.xcarchive \
  -derivedDataPath /private/tmp/wiki-tour-release -allowProvisioningUpdates archive
```

Upload for internal TestFlight testing:

```sh
xcodebuild -exportArchive -archivePath /private/tmp/WikiTour-TestFlight-v4.xcarchive \
  -exportOptionsPlist docs/TestFlightExportOptions.plist \
  -exportPath /private/tmp/wiki-tour-testflight-export -allowProvisioningUpdates
```

The export options select internal TestFlight distribution, automatic signing, symbol upload, and build-number management. This does not submit a public App Store release. Review processing and export compliance in App Store Connect after upload.

Verification: 9 unit tests and 4 UI tests pass, including saving/reopening/deleting walks across relaunches, independent draft storage, route snapshots, Wikipedia discovery and errors, and edge-to-edge sheet behavior. The final signed Release archive builds successfully.

App Store Connect: https://appstoreconnect.apple.com/apps/6815961925/testflight

Build 1 uploaded successfully on September 25, 2026 at 01:55 EDT. Build 2 used the intermediate singular name; build 3 is the final plural-name build.

Build 3 uploaded successfully at 01:59 EDT with `CFBundleDisplayName = Wiki Walking Tours`. Logs: `/private/tmp/wiki-tour-archive-v3.log` and `/private/tmp/wiki-tour-upload-v3.log`. The Personal testing internal group has automatic distribution enabled and Jenna Xu is its sole tester.

Export compliance for build 3: selected “None of the algorithms mentioned above.” The app uses system URLSession/MapKit networking and FirebaseCore only; it does not link Firebase Auth, Firestore/gRPC, OpenSSL, or BoringSSL. Reassess if future SDK additions change that. Apple guidance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance

Final status verified September 25, 2026: build 1.0 (3), ID `732656c8-b98b-4de1-93b6-2760938b7a48`, has processing state `VALID` and internal state `IN_BETA_TESTING`. It is assigned to Personal testing (`d289f510-5242-42bb-8c32-3c2aef42927c`) with one tester. The App Store Connect record and archived display name are both **Wiki Walking Tours**. Earlier builds 1 and 2 were superseded during naming and are not the designated test build.

## Build 4: map rendering corrections

The route now resolves the named AccentColor asset directly instead of MapKit's contextual accent (which displayed blue on the device). The collapsed route panel extends its gray surface under the bottom safe area, while keeping its text and button above the home indicator. The location control now uses the Figma white arrow asset and translucent circle. A UI regression test checks the collapsed panel's full width and bottom edge.

Build 4 verification: 9 unit tests and 5 UI tests passed (`Test-WikiTour-2026.09.25_10-44-42--0400.xcresult`). A normal Release simulator build was inspected with live saved stops and walking directions: `/private/tmp/wiki-tour-map-release-fixed.png` shows pink route dots and full gray coverage under the home indicator. Release archive: `/private/tmp/WikiTour-TestFlight-v4.xcarchive`.

## Build 5: stable drawer dragging

Drawer gestures now measure translation in global screen coordinates, with a stable starting height. The interactive height and selected detent settle together in one animation transaction, avoiding the independent gesture-state reset that caused release snap-back. The grab target is 200 × 44 points while retaining the small visible capsule. A downward tour flick snaps to the collapsed detent instead of dismissing the walk; other drawers require an actual pull below their minimum height to dismiss.

The sheet UI regression test now performs repeated upward/downward drags from outside the visible capsule, checks expanded/collapsed state and tour controls, and verifies the bottom edge remains flush. Build 5 also includes build 4's pink route dots, bottom safe-area coverage, and Figma location control.

Build 5 verification: all 9 unit tests passed. Drawer, bookmark, safe-area, and walking-navigation UI tests passed in the full run. The saved-walk test missed its draft-navigation tap while the library sheet was opening; the isolated save/relaunch/delete rerun passed (22.6 seconds). Results: `Test-WikiTour-2026.09.25_10-53-27--0400.xcresult` and `Test-WikiTour-2026.09.25_10-55-30--0400.xcresult`. Release simulator build and signed archive succeeded. Upload completed at 10:55:55 EDT on September 25, 2026. The simulator was restored to the normal Release app with existing saved data.

Final distribution verified: build **1.0 (5)** (`03a99546-18cb-4841-93ca-35be022b6b22`) is `VALID` and `IN_BETA_TESTING`, assigned to the **Personal testing** internal group. The unchanged export-compliance declaration and testing notes were saved. Build 5 supersedes build 4.

## Build 6: updated maps, landmarks, walks, and app icon

Includes the Figma marker refresh (saved pink circles, active pin with larger emoji and 16 pt label, location dot, hidden-landmark dots), saved-marker priority, stronger map controls, top-right landmark bookmark, introduction-only Wikipedia descriptions and tighter paragraph spacing, emoji-only photo fallbacks, improved landmark emoji classification, route clearing on check/Finish, save/unsave walk hearts, and the shoe icon with a halftone sky background.

Validation: 13 unit tests and all 6 UI tests passed in `Test-WikiTour-2026.09.26_16-33-28--0400.xcresult`. Signed Release archive succeeded at `/private/tmp/WikiTour-TestFlight-v6.xcarchive`. The first export/upload request timed out; upload was retried using the same archive. Upload succeeded at 16:45:39 EDT on September 26, 2026 after two cloud-signing timeouts. Log: `/private/tmp/wiki-tour-upload-v6-retry2.log`. Final status verified: build `f9f722ee-9295-48ee-9623-5f4b4c816457` is `VALID` and `IN_BETA_TESTING`, assigned to the Personal testing internal group. The unchanged export-compliance declaration and testing notes were saved. Build 6 supersedes build 5.

## Build 7: Walking Tours device name

Renamed CFBundleDisplayName and the location-permission explanation to Walking Tours. Signed archive and Release simulator build passed; archived display name and version were verified. Uploaded September 26, 2026 at 17:06:41 EDT. Build `c613a527-9c72-4203-8d17-5c94d2c34d26` is VALID and IN_BETA_TESTING in Personal testing, with compliance and notes saved.

Apple rejected Walking Tours as the App Store Connect listing name because it is already used by a different account (409 duplicate-name response). The listing remains Wiki Walking Tours pending the user's alternative; the installed app displays Walking Tours. Bundle ID and saved data are unchanged.

## Build 8: automatic walking tour and zoom-preserving focus

As soon as nearby landmarks load, the ten closest to the user's location become the current walk and walking directions are requested, matching the web app. Panning the map or tapping Search this area keeps the current walk. A new device location replaces the suggestion only while it is untouched, and editing it makes it the user's own draft. Tapping a landmark, or stepping through walk stops, now pans to it at the user's current zoom instead of a fixed zoom.

Validation: 14 unit tests and all 6 UI tests passed in `Test-WikiTour-2026.10.03_00-00-51--0400.xcresult`. Signed Release archive: `/private/tmp/WikiTour-TestFlight-v8.xcarchive` (log `/private/tmp/wiki-tour-archive-v8.log`). Uploaded October 3, 2026 at 00:04:49 EDT (log `/private/tmp/wiki-tour-upload-v8.log`). Processing status, export compliance, and testing notes still need to be confirmed in App Store Connect.

## Build 9: export compliance declared in the app

Build 8 did not appear for testers. It was uploaded without errors or warnings, so it most likely waited on the manual export-compliance question, as builds 3 through 7 did. Build 9 has the same code and declares `ITSAppUsesNonExemptEncryption = NO` in the generated Info.plist. That matches the earlier answer, "None of the algorithms mentioned above." App Store Connect should no longer hold new builds for that question. Reassess the declaration if encryption-related SDKs are added.

Signed archive: `/private/tmp/WikiTour-TestFlight-v9.xcarchive` (log `/private/tmp/wiki-tour-archive-v9.log`). Uploaded October 3, 2026 at 15:44:39 EDT (log `/private/tmp/wiki-tour-upload-v9.log`). No App Store Connect API key is configured on this Mac, so processing status was not verified from the command line.

Verified in App Store Connect at 15:48 EDT: build 9 shows Testing in the Personal testing group, and build 8 shows Missing Compliance, confirming the cause.

## Build 10: heritage discovery, driving tours, heading-up walks, and Keep going

- Discovery prefers officially designated places from Wikidata (National Register, city landmarks, and equivalent registers abroad), topped up by whole-word Wikipedia matches. Ordinary schools are no longer included unless designated. Stations, historic districts, and neighborhoods are excluded, including by Wikidata type.
- Suggested tours: up to 10 stops within a 75-minute walk when at least two places are within a 20-minute walk; otherwise a driving tour of up to 10 stops within 6 miles. Stops are chosen by distance alone and ordered so the route does not double back. The map zooms to fit each suggested tour.
- Emoji use Wikidata place types and new categories (fountains, statues, ruins, hotels, restaurants, shops, offices, hospitals, squares).
- Walk sheet: description text matches place cards, the current stop uses the active pin, the map turns toward the current stop at street level, Back is visibly disabled on the first stop, and the last stop offers Keep going.
- Directions are cached per leg and retried after Apple's rate limit resets, fixing "Route unavailable" after several quick edits in build 9.
- Solid route line and fixed saved-marker shadow.

Validation: 23 unit tests and 6 UI tests passed on this code. Signed archive: `/private/tmp/WikiTour-TestFlight-v10.xcarchive` (log `/private/tmp/wiki-tour-archive-v10.log`). Uploaded October 3, 2026 at 18:07:39 EDT (log `/private/tmp/wiki-tour-upload-v10.log`). The build declares no non-exempt encryption, so it should not wait on export compliance.

## Build 11: welcome postcard, loading screen, and searching other areas

- A new suggested tour opens with the welcome postcard from Figma (25:486 / 23:230): the first stop's Wikipedia photo with matched image adjustments and a pink halftone, the neighborhood name in Borel, Brandon Grotesque and Brandon Text lettering, and a tap to start. Neighborhood names come from OpenStreetMap, with Apple's geocoder as a fallback.
- First-load screen: the docbotic.care sky video under a dark halftone with the app icon's shoe, a spinner, and status caption; the launch screen shows the same shoe on the sky's average color.
- Search this area builds a new tour (and postcard) for the searched area, starting from the searched spot when the user is elsewhere; the postcard is named for the middle of the tour.
- Walk view zooms out just enough to show where each leg starts. Historic districts are no longer tour stops. The Search this area button matches the map buttons.

Validation: 27 unit tests and 8 UI tests passed on this code. Signed archive: `/private/tmp/WikiTour-TestFlight-v11.xcarchive` (log `/private/tmp/wiki-tour-archive-v11.log`). Uploaded October 4, 2026 at 15:46 EDT (log `/private/tmp/wiki-tour-upload-v11.log`). Brandon Grotesque and Brandon Text are commercial fonts bundled at the owner's request for this unpublished, internal-only app.
