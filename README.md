# WikiTour iOS

A native iOS walking-tour app that uses your GPS location to find nearby historical landmarks via the [Wikipedia Geosearch API](https://www.mediawiki.org/wiki/API:Geosearch) and builds a self-guided walking tour — no API key required.

## Features

- **Live location** — uses CoreLocation to detect where you are
- **Map view** — interactive map with landmark pins; tap any pin for a summary card
- **Tour list** — ordered list of nearby stops numbered by walking distance
- **Detail view** — Wikipedia extract, hero photo, and one-tap walking directions via Apple Maps
- **Auto-refresh** — re-fetches landmarks after you move more than 200 m

## Requirements

| Tool | Version |
|---|---|
| Xcode | 15 or later |
| iOS deployment target | 17.0 |
| Swift | 5.9 |

No third-party dependencies — only Apple frameworks (SwiftUI, MapKit, CoreLocation).

## Getting started

1. Clone this repo and open `WikiTour.xcodeproj` in Xcode 15+.
2. Select your development team in **Signing & Capabilities** (or leave empty for Simulator).
3. Build and run on a device or Simulator.
   In the Simulator, use **Features → Location** to simulate a location (e.g. "Apple" or a custom GPS coordinate).

## Project structure

```
WikiTour/
├── WikiTourApp.swift          # App entry point
├── ContentView.swift          # Root TabView + location-denied fallback
├── Models/
│   └── Landmark.swift         # Data model + Wikipedia API response types
├── Services/
│   └── WikipediaService.swift # Wikipedia Geosearch + Summary API client
├── ViewModels/
│   └── TourViewModel.swift    # Location manager + data orchestration (@Observable)
├── Views/
│   ├── TourMapView.swift      # Full-screen MapKit map with floating header & landmark card
│   ├── TourListView.swift     # Numbered tour stop list
│   └── LandmarkDetailView.swift # Article extract, photo, directions
└── Assets.xcassets
```

## APIs used

| API | Endpoint |
|---|---|
| Wikipedia Geosearch | `https://en.wikipedia.org/w/api.php?action=query&list=geosearch&…` |
| Wikipedia Summary | `https://en.wikipedia.org/api/rest_v1/page/summary/{title}` |

Both are free, unauthenticated, and subject to the [Wikimedia API terms of use](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use).
