# GPS Tracker iOS

A modern, real-time GPS tracking application built with SwiftUI and MapKit. This app allows users to record their movements, mark points of interest (POI), monitor GPS signal health, and export their tracks to standardized GPX files.

## ✨ Features

- **Real-time Tracking**: Precise location tracking using CoreLocation with smooth path rendering on the map.
- **Map Integration**: Interactive MapKit interface with user location tracking, compass, and scale.
- **Recording Controls**: Start and stop tracking whenever you want to save battery or manage track segments.
- **Points of Interest (POI)**: Mark specific locations with a single tap. POIs are displayed on the map and saved in the export.
- **Live Stats**: Monitor current speed (km/h), altitude (m), total distance, and the number of recorded points in real-time.
- **Odometer**: Cumulative distance calculation for your track with smart noise filtering.
- **GPS Status Monitor**: Detailed view of signal accuracy, vertical accuracy, course, and signal quality indicator.
- **GPX Export**: Export your recorded tracks and waypoints as standardized `.gpx` files for use in Google Earth, Strava, or other GIS tools.
- **Modern UI**: Clean, glassmorphism design using SwiftUI's `.ultraThinMaterial`.

## 📸 Screenshots

*(Add screenshots here after running the app)*

## 🚀 Getting Started

### Prerequisites
- macOS with Xcode 15.0 or later.
- An iOS device (recommended for best GPS results) or iOS Simulator.

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/jasonleecode/gps-tracker-ios.git
   ```
2. Open `gps-tracker.xcodeproj` in Xcode.
3. Select your target device and press `Cmd + R` to build and run.

### Permissions
The app requires the following permissions to function:
- `NSLocationWhenInUseUsageDescription`: Required to show and track your location while using the app.
- `NSLocationAlwaysAndWhenInUseUsageDescription`: Required for background tracking (if configured).

## 🛠 Tech Stack
- **SwiftUI**: Modern declarative UI framework.
- **MapKit**: High-performance mapping and location visualization.
- **CoreLocation**: Robust location data management.
- **Combine**: For reactive state management between the location manager and the UI.

## 📄 License
This project is available under the MIT License.
