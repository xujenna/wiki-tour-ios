# WikiTour iOS

A native iOS port of [wiki-tour](https://github.com/xujenna/wiki-tour). Uses your GPS location to build a self-guided walking tour of nearby sites on the **National Register of Historic Places**, sourced entirely from Wikipedia — no API key required.

## How it works

1. **Locate** — one-shot GPS fix via CoreLocation
2. **Reverse-geocode** — CLGeocoder determines your county + state
3. **Look up NRHP listings** — fetches the Wikipedia page
   `National Register of Historic Places listings in {County}, {State}`
   (with special-cased names for NYC boroughs)
4. **Parse section structure** — handles three page layouts:
   - *Current listings / Listings county-wide* → section 1 links
   - *Listings by town / Lists by area* → intermediate links → per-town section 1 links
   - Empty sections (renamed page) → follows NRHP link from the page
5. **Fetch summaries** — concurrently calls Wikipedia REST `/page/summary/{title}` for every linked article; keeps only those with coordinates
6. **Filter** — drops articles whose title includes `, {State}` or `National Park Service`
7. **Route** — picks the 10 closest sites and orders them using a nearest-neighbour greedy algorithm (same as Google Maps `optimizeWaypoints` in the original)
8. **Display** — numbered markers on a MapKit map + a straight-line route polyline; tap any stop for the full Wikipedia extract and one-tap Apple Maps walking directions

## Requirements

| | |
|---|---|
| Xcode | 15+ |
| iOS deployment target | 17.0 |
| Swift | 5.9 |

No third-party dependencies — SwiftUI, MapKit, CoreLocation only.

## Getting started

1. Open `WikiTour.xcodeproj` in Xcode 15+.
2. Set your development team in **Signing & Capabilities** (or leave blank for Simulator).
3. Build and run.
   In Simulator, use **Features → Location** to test with a real city (e.g. set a custom coordinate for Manhattan, Brooklyn, or any US county).

## Project structure

```
WikiTour/
├── WikiTourApp.swift
├── ContentView.swift          # Loading screen → Tab view (map + list)
├── Models/
│   └── Landmark.swift         # Landmark model + all Wikipedia API response types
├── Services/
│   └── WikipediaService.swift # NRHP page parsing, concurrent summary fetching,
│                              # nearest-neighbour route optimisation
├── ViewModels/
│   └── TourViewModel.swift    # CoreLocation + CLGeocoder + tour orchestration
├── Views/
│   ├── TourMapView.swift      # MapKit map with numbered stop markers + route polyline
│   ├── TourListView.swift     # Ordered stop list
│   └── LandmarkDetailView.swift # Wikipedia extract, photo, Apple Maps directions
└── Assets.xcassets
```

## APIs used

| API | Purpose |
|---|---|
| `en.wikipedia.org/w/api.php?action=parse&prop=sections` | Inspect NRHP page structure |
| `en.wikipedia.org/w/api.php?action=parse&prop=links&section=1` | Get landmark article links |
| `en.wikipedia.org/api/rest_v1/page/summary/{title}` | Coordinates, extract, thumbnail |

All free, unauthenticated, [Wikimedia terms of use](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use).
