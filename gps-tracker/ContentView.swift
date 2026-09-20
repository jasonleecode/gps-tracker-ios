import SwiftUI
import MapKit

enum TrackingMode {
    case follow  // camera follows and rotates to the direction of travel
    case free    // camera stays put; the arrow moves across the map
}

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSatelliteStatus = false
    @State private var trackingMode: TrackingMode = .follow
    @State private var cameraHeading: Double = 0
    @State private var cameraDistance: Double = 1200
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if locationManager.isRecording, let location = locationManager.location {
                    // Keyed by timestamp so SwiftUI recreates the annotation on every
                    // location update — a plain Annotation keeps its initial coordinate.
                    ForEach([location], id: \.timestamp) { loc in
                        Annotation("", coordinate: loc.coordinate) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 3)
                                .rotationEffect(.degrees((locationManager.movementDirection ?? 0) - cameraHeading))
                        }
                    }
                } else {
                    UserAnnotation()
                }

                if locationManager.path.count > 1 {
                    MapPolyline(coordinates: locationManager.path.map { $0.coordinate })
                        .stroke(.orange, lineWidth: 5)
                }

                ForEach(locationManager.pois) { poi in
                    Marker(poi.name, systemImage: "mappin.and.ellipse", coordinate: poi.coordinate)
                        .tint(.orange)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                cameraHeading = context.camera.heading
                cameraDistance = context.camera.distance
            }
            // Full-bleed map, but keep the map controls (user location button,
            // compass, scale) below the status bar so they don't overlap it.
            .safeAreaPadding(.top, 60)
            .ignoresSafeArea()

            if isLandscape {
                landscapeOverlay
            } else {
                portraitOverlay
            }
        }
        .sheet(isPresented: $showSatelliteStatus) {
            SatelliteStatusView(locationManager: locationManager)
        }
        .onChange(of: locationManager.isRecording) { _, recording in
            if recording { applyTrackingMode() }
        }
        .onChange(of: trackingMode) { _, _ in
            if locationManager.isRecording { applyTrackingMode() }
        }
        .onChange(of: locationManager.location) { _, location in
            guard locationManager.isRecording, trackingMode == .follow, let location else { return }
            followCamera(to: location)
        }
    }

    // Follow mode drives the camera manually instead of using .userLocation(followsHeading:),
    // because that camera mode renders the system blue dot on top of our arrow annotation.
    private func followCamera(to location: CLLocation) {
        position = .camera(MapCamera(
            centerCoordinate: location.coordinate,
            distance: cameraDistance,
            heading: locationManager.movementDirection ?? cameraHeading
        ))
    }

    private func applyTrackingMode() {
        switch trackingMode {
        case .follow:
            if let location = locationManager.location {
                followCamera(to: location)
            }
        case .free:
            position = .automatic
        }
    }

    // Portrait: controls stacked vertically, buttons and stats pinned to the bottom
    private var portraitOverlay: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                controlButtons
                Spacer()
            }
            .padding(.top, 10)

            Spacer()

            actionButtons

            statsCard
        }
    }

    // Landscape: controls top-left, buttons and stats in a scrollable right-hand column
    private var landscapeOverlay: some View {
        HStack(alignment: .top, spacing: 0) {
            controlButtons
                .padding(.top, 10)

            Spacer()

            ScrollView {
                VStack(spacing: 12) {
                    actionButtons
                    statsCard
                }
                .padding(.trailing, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Unified Top-Left Controls
    private var controlButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            // GPS Status Button
            Button(action: {
                showSatelliteStatus.toggle()
            }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            // Tracking Mode Toggle (only while recording)
            if locationManager.isRecording {
                Button(action: {
                    trackingMode = trackingMode == .follow ? .free : .follow
                }) {
                    Image(systemName: trackingMode == .follow ? "location.north.circle.fill" : "map.circle.fill")
                        .font(.title3)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }

            // Share/Export Button
            if !locationManager.path.isEmpty || !locationManager.pois.isEmpty,
               let gpxURL = locationManager.exportAsGPXFile() {
                ShareLink(item: gpxURL, preview: SharePreview(gpxURL.lastPathComponent, image: Image(systemName: "map"))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }

            // Delete/Clear Button
            if !locationManager.path.isEmpty || !locationManager.pois.isEmpty {
                Button(role: .destructive, action: {
                    locationManager.clearAll()
                }) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.leading)
    }

    // Action Buttons (Start/Stop & POI)
    private var actionButtons: some View {
        HStack(spacing: isLandscape ? 10 : 20) {
            Button(action: {
                locationManager.toggleRecording()
            }) {
                HStack {
                    Image(systemName: locationManager.isRecording ? "stop.circle.fill" : "play.circle.fill")
                    Text(locationManager.isRecording ? "Stop" : "Start")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(locationManager.isRecording ? Color.red : Color.green)
                .cornerRadius(12)
            }

            Button(action: {
                locationManager.addPOI()
            }) {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text("POI")
                }
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, isLandscape ? 0 : nil)
    }

    // Stats Card — dark high-contrast panel, readable in bright outdoor light
    @ViewBuilder
    private var statsCard: some View {
        if let location = locationManager.location {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.orange)
                    Text("Current Position")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    if locationManager.isRecording {
                        Label("REC", systemImage: "record.circle")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    }
                }

                panelDivider

                // Main Stats Grid
                VStack(spacing: 12) {
                    HStack(spacing: 15) {
                        StatBox(label: "Speed", value: String(format: "%.1f km/h", (location.speed > 0 ? location.speed : 0) * 3.6))
                        StatBox(label: "Altitude", value: String(format: "%.0f m", location.altitude))
                    }
                    HStack(spacing: 15) {
                        StatBox(label: "Distance", value: formatDistance(locationManager.totalDistance))
                        StatBox(label: "Points", value: "\(locationManager.path.count)")
                    }
                }

                panelDivider

                // Coordinates
                HStack {
                    VStack(alignment: .leading) {
                        Text("Latitude")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                        Text(String(format: "%.6f°", location.coordinate.latitude))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Longitude")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                        Text(String(format: "%.6f°", location.coordinate.longitude))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.72))
            .cornerRadius(15)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8)
            .padding(.horizontal, isLandscape ? 0 : nil)
            .padding(.bottom, isLandscape ? 0 : 30)
        }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.2f km", meters / 1000)
        }
    }
}

struct SatelliteStatusView: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss

    private var location: CLLocation? { locationManager.location }

    var body: some View {
        NavigationView {
            List {
                if locationManager.accuracyAuthorization == .reducedAccuracy {
                    Section {
                        Label("Precise Location is off — accuracy is limited to ~1–2 km.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Button("Enable Precise Location") {
                            locationManager.requestTemporaryFullAccuracy()
                        }
                    }
                }

                if let location = location {
                    Section("Signal Quality") {
                        HStack {
                            Text("Accuracy")
                            Spacer()
                            Text(String(format: "±%.1f m", location.horizontalAccuracy))
                                .foregroundColor(accuracyColor(location.horizontalAccuracy))
                        }
                        
                        HStack {
                            Text("Signal Level")
                            Spacer()
                            SignalIndicator(accuracy: location.horizontalAccuracy)
                        }
                    }
                    
                    Section("Detailed Metadata") {
                        LabeledContent("Vertical Accuracy", value: String(format: "±%.1f m", location.verticalAccuracy))
                        LabeledContent("Course", value: location.course >= 0 ? String(format: "%.1f°", location.course) : "--")
                        LabeledContent("Timestamp", value: location.timestamp.formatted(date: .omitted, time: .standard))
                        
                        if #available(iOS 15.0, *) {
                            LabeledContent("Source", value: location.sourceInformation?.isSimulatedBySoftware == true ? "Simulated" : "GPS/Hardware")
                        }
                    }
                } else {
                    Text("No GPS data available")
                }
            }
            .navigationTitle("GPS Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy < 10 { return .green }
        if accuracy < 30 { return .orange }
        return .red
    }
}

struct SignalIndicator: View {
    let accuracy: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < signalBars ? .green : .gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(index + 1) * 4)
            }
        }
    }
    
    var signalBars: Int {
        if accuracy < 5 { return 5 }
        if accuracy < 10 { return 4 }
        if accuracy < 30 { return 3 }
        if accuracy < 100 { return 2 }
        return 1
    }
}

struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.white.opacity(0.55))
                .textCase(.uppercase)
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ContentView()
}
