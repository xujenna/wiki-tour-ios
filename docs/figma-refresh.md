# September 26 mock refresh

Source: https://www.figma.com/design/rFy00JQ033W3LjIo7U1opp/i-guess-we-re-stuck-here?node-id=5-489

Compared map/card, collapsed route, active tour, library, and saved tour designs (4:72, 4:181, 4:301, 4:422, 6:584, 6:662).

- Selected landmark: original pink pin SVG from 4:119, 60 × 68 pt body with 32 pt dynamic landmark emoji; tip anchored to the coordinate. Saved, unselected landmarks retain 40 pt circles and bookmarks.
- Compact route metrics (mi/min), a shared header with heart and clear/delete actions, and revised typography. Bottom safe-area coverage and interactive sheet resizing are retained.
- Map save/location buttons retain the existing Figma icons (30/24 pt inside 40 pt circles). Per the follow-up request, backgrounds are darker with a subtle white outline; label placement reserves their corner.
- Landmark text still loads only Wikipedia's full introduction. API photos and map data remain dynamic.
- Emoji classification uses Wikipedia's place-type clause before location text, whole-word matches, and specific landmark types. Bookstores use books and food co-ops use a grocery cart. Generic park/forest words in neighborhood names no longer classify the place as a park.

The existing card distance uses available straight-line location distance; the mock's walking ETA on individual place cards is a pre-existing gap, not an invented estimate. Route summaries continue to use actual walking directions.

Follow-up refinements: missing-photo placeholders show only the emoji, without a caption. Introduction paragraphs render separately with 10 pt gaps, matching the mock's paragraph spacing rather than adding blank text lines.

Validation: 11 unit tests and 6 UI tests passed in `Test-WikiTour-2026.09.26_15-24-28--0400.xcresult`. Following placeholder/paragraph refinements, the two affected UI flows passed again in `Test-WikiTour-2026.09.26_15-27-33--0400.xcresult`. Screenshots were reviewed for the active pin, collapsed/expanded route controls, stronger map buttons, paragraph spacing, and emoji-only fallback. The final Release simulator build succeeded and was installed. TestFlight remains build 5.

Further interaction refinements: the walk heart toggles save/unsave, including on reopened walks. Unsaving removes the persisted library entry but keeps the displayed route, metrics, and current stop; the independent draft is preserved. Saving again retains the walk's name. Per user request, the trash action and confirmation dialog were removed; the check consistently clears the current route.

Saved-marker revision (14:749): saved and active-route landmarks use the mock's #FF9CF7 circle fill with a 2 pt #FF00EA outline, 40 pt diameter and 24 pt emoji. Removed the small bookmark badge. The selected landmark continues to use the separate pink pin.

Hidden-marker revision: unsaved landmarks that do not fit a full marker now retain a tappable 10 pt dot using the original 14:784 SVG. Dots do not reserve collision space and render before full markers. Saved/route stops remain full markers, and selecting a dot promotes it to the active pin. Dense-layout and saved-priority regression checks pass.

Landmark sheet revision (4:72): moved the bookmark to the top-right of the hero, replacing the close icon. The sheet still dismisses by dragging the handle down or using the accessibility escape action.

Active-marker revision (4:72 / 4:119): updated the original pin SVG to the light-pink fill and bright-pink 2 pt outline. The active landmark now shows a label beside the pin when space permits, retaining the shared 14 pt marker typography requested by the user. Layout reserves its label bounds and anchors the pin tip correctly.

Active-marker correction: added the original 10 pt dot from 14:825, anchored at its center beneath the pin. Active label is now 16 pt with 0.16 tracking per the latest request; compensated the emoji asset’s 144/120 canvas padding to match the mock’s 32 pt glyph.
