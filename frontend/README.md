# GeoGhost - Street Art Collector

An offline-first Flutter application for collecting street art (stickers, graffiti, murals) you find on the street, with a Map + Dynamic Bottom Sheet architecture.

> **Note**: The project folder is named "frontend" for organizational purposes, but the application itself is called "GeoGhost".

## Features

- 📸 **Camera Integration**: Capture street art with location tagging. The camera only runs while the capture panel is open, keeping the device cool.
- 🏷️ **Auto-Tagging**: On-device ML Kit image labeling suggests tags for each photo — free, offline, no API calls.
- 🗺️ **Interactive Map**: All collected artwork shown as photo-thumbnail markers on an OpenStreetMap map (no API key required).
- 💾 **Offline-First**: All data stored locally in SQLite via drift. The entire app works without a network connection (map tiles aside).
- 🎨 **Dynamic UI**: Sliding bottom panel with context-aware content.
- 📱 **Cross-Platform**: Works on both iOS and Android.

## Architecture

- **State Management**: flutter_bloc
- **Local Database**: drift (SQLite)
- **Maps**: flutter_map + OpenStreetMap tiles (zero API cost)
- **Camera**: camera plugin, lazily initialized/disposed with the panel
- **Image Processing**: flutter_image_compress (native codecs, off the UI thread)
- **Tag Suggestions**: google_mlkit_image_labeling (on-device)
- **UI Pattern**: Map + DraggableScrollableSheet bottom panel

## Setup Instructions

### Prerequisites

- Flutter SDK 3.8.1+
- Android Studio / Xcode (iOS deployment target is 15.5, required by ML Kit)

No API keys are needed — the map uses OpenStreetMap.

### Run

```bash
cd frontend
flutter pub get
dart run build_runner build   # generates drift database code
flutter run
```

## Project Structure

```
lib/
├── blocs/           # BLoC state management
│   ├── map_bloc.dart
│   ├── map_event.dart
│   └── map_state.dart
├── models/          # Data models
│   └── artwork.dart
├── pages/           # Screen widgets
│   ├── home_page.dart
│   ├── confirmation_screen.dart
│   └── artwork_detail_screen.dart
├── services/        # Business logic services
│   ├── database_service.dart   # drift table + queries
│   └── labeling_service.dart   # ML Kit tag suggestions
├── widgets/         # Reusable UI components
│   ├── integrated_camera_panel.dart
│   └── artwork_preview_panel.dart
└── main.dart        # App entry point
```

## Key Implementation Notes

### Camera Lifecycle
The camera is initialized only when the bottom panel is opened past a threshold and fully disposed when it slides back down or the app goes inactive. This keeps heat and battery drain to a minimum while browsing the map.

### Image Pipeline
On save, the photo is compressed natively (max 1920px, JPEG q75) and a ~200px thumbnail is generated for map markers. Both run off the UI thread.

### Tag Suggestions
After a photo is taken, ML Kit image labeling runs on-device and suggests tags (confidence > 0.6) as toggleable chips on the confirmation screen. Failures degrade silently to manual input.

### iOS Simulator Limitation
ML Kit ships binary frameworks without an arm64-simulator slice, so the app does not build for the iOS Simulator on Apple Silicon. Build and test on a physical device (which the camera/GPS features require anyway); Android emulators are unaffected.

### Map Tiles
OpenStreetMap's public tile server is used with a proper user agent, per the [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/). For heavier usage, switch `urlTemplate` to a commercial tile provider.

## Permissions Required

### Android
- `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`

### iOS
- `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`

## Future Enhancements

- [ ] Gallery/list view of the collection
- [ ] Cloud sync functionality
- [ ] Social sharing features
- [ ] Advanced filtering and search
- [ ] Export functionality

## License

This project is licensed under the MIT License - see the LICENSE file for details.
