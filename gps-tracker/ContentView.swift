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
    @State private var showFiles = false
    @State private var showSettings = false
    @AppStorage("mapStyle") private var mapStyleSetting = "standard"
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("useImperialUnits") private var useImperialUnits = false
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    // Stats panel can collapse to a compact strip; recording auto-collapses
    // it after 10 seconds.
    @State private var isPanelCompact = false
    @State private var compactTimer: Task<Void, Never>?
    @State private var trackingMode: TrackingMode = .follow
    @State private var cameraHeading: Double = 0
    @State private var cameraDistance: Double = 1200
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private func t(_ key: String) -> String { L10n.text(key, appLanguage) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if locationManager.isRecording, let location = locationManager.location {
                    // Keyed by timestamp so SwiftUI recreates the annotation on every
                    // location update — a plain Annotation keeps its initial coordinate.
                    ForEach([location], id: \.timestamp) { loc in
                        Annotation("", coordinate: CoordinateConverter.wgs84ToGcj02(loc.coordinate)) {
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

                ForEach(Array(locationManager.trackSegments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(speedColor(segment.speedFraction), lineWidth: 5)
                }

                ForEach(locationManager.pois) { poi in
                    Marker(poi.name, systemImage: "mappin.and.ellipse", coordinate: CoordinateConverter.wgs84ToGcj02(poi.coordinate))
                        .tint(.orange)
                }
            }
            .mapStyle(mapStyleSetting == "satellite" ? .hybrid : .standard)
            .mapControls {
                // Landscape uses the custom userLocationButton in the controls row.
                if !isLandscape {
                    MapUserLocationButton()
                }
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
        .sheet(isPresented: $showFiles) {
            FilesView(locationManager: locationManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
        .onChange(of: keepScreenOn) { _, keepOn in
            UIApplication.shared.isIdleTimerDisabled = keepOn
        }
        .onChange(of: locationManager.isRecording) { _, recording in
            if recording {
                applyTrackingMode()
                // Start in full mode, then auto-collapse to the compact strip.
                isPanelCompact = false
                compactTimer?.cancel()
                compactTimer = Task {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    withAnimation { isPanelCompact = true }
                }
            } else {
                compactTimer?.cancel()
            }
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
    // Maps a 0...1 speed fraction to a hue: 0 (slowest) is red, 1 (fastest) is blue.
    private func speedColor(_ fraction: Double) -> Color {
        Color(hue: 2.0 / 3.0 * fraction, saturation: 0.85, brightness: 0.95)
    }

    private func followCamera(to location: CLLocation) {
        position = .camera(MapCamera(
            centerCoordinate: CoordinateConverter.wgs84ToGcj02(location.coordinate),
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

            statsCard

            actionButtons
        }
    }

    // Landscape: all circular controls and the action buttons live in a
    // scrollable right-hand column, stats below.
    private var landscapeOverlay: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer()

            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        gpsStatusButton
                        trackingModeButton
                        userLocationButton
                        shareButton
                        deleteButton
                        Spacer()
                    }

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
        .padding(.top, 10)
    }

    // Portrait-only top-left controls; in landscape all of these move to a
    // row above the action buttons (see landscapeOverlay).
    private var controlButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            gpsStatusButton
            trackingModeButton
            shareButton
            deleteButton
        }
        .padding(.leading)
    }

    private var gpsStatusButton: some View {
        Button(action: {
            showSatelliteStatus.toggle()
        }) {
            circleButtonLabel("antenna.radiowaves.left.and.right")
        }
    }

    @ViewBuilder
    private var trackingModeButton: some View {
        // Tracking Mode Toggle (only while recording)
        if locationManager.isRecording {
            Button(action: {
                trackingMode = trackingMode == .follow ? .free : .follow
            }) {
                circleButtonLabel(trackingMode == .follow ? "location.north.circle.fill" : "map.circle.fill")
            }
        }
    }

    // Re-centers the map on the user. A custom button is used instead of
    // MapUserLocationButton because the system control's position is fixed.
    private var userLocationButton: some View {
        Button(action: {
            position = .userLocation(fallback: .automatic)
        }) {
            circleButtonLabel("location.fill")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if !locationManager.path.isEmpty || !locationManager.pois.isEmpty,
           let gpxURL = locationManager.exportAsGPXFile() {
            ShareLink(item: gpxURL, preview: SharePreview(gpxURL.lastPathComponent, image: Image(systemName: "map"))) {
                circleButtonLabel("square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if !locationManager.path.isEmpty || !locationManager.pois.isEmpty {
            Button(role: .destructive, action: {
                locationManager.clearAll()
            }) {
                circleButtonLabel("trash")
            }
        }
    }

    private func circleButtonLabel(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    // Action Buttons (Start/Stop, POI, Files & Setting)
    private var actionButtons: some View {
        HStack(spacing: isLandscape ? 8 : 12) {
            Button(action: {
                locationManager.toggleRecording()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: locationManager.isRecording ? "stop.circle.fill" : "play.circle.fill")
                    Text(locationManager.isRecording ? t("Stop") : t("Start"))
                }
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(locationManager.isRecording ? Color.red : Color.green)
                .cornerRadius(12)
            }

            secondaryActionButton(title: t("POI"), icon: "mappin.and.ellipse", color: .orange) {
                locationManager.addPOI()
            }
            secondaryActionButton(title: t("Files"), icon: "folder", color: .blue) {
                showFiles = true
            }
            secondaryActionButton(title: t("Setting"), icon: "gearshape", color: .gray) {
                showSettings = true
            }
        }
        .padding(.horizontal, isLandscape ? 0 : nil)
        .padding(.bottom, isLandscape ? 0 : 8)
    }

    private func secondaryActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(color)
            .cornerRadius(12)
        }
    }

    // Stats panel: full card or compact strip. Tap toggles between the two.
    @ViewBuilder
    private var statsCard: some View {
        if let location = locationManager.location {
            if isPanelCompact {
                compactStatsCard(location: location)
            } else {
                fullStatsCard(location: location)
            }
        }
    }

    // Compact strip: speed, altitude and distance only.
    private func compactStatsCard(location: CLLocation) -> some View {
        HStack(spacing: 0) {
            compactStat(label: t("Speed"), value: formatSpeed(location.effectiveSpeed))
            compactStat(label: t("Altitude"), value: formatAltitude(location.altitude))
            compactStat(label: t("Distance"), value: formatDistance(locationManager.totalDistance))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.72))
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8)
        .padding(.horizontal, isLandscape ? 0 : nil)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { isPanelCompact = false }
        }
    }

    private func compactStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .rounded).bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // Full stats card — dark high-contrast panel, readable in bright outdoor light
    private func fullStatsCard(location: CLLocation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.orange)
                    Text(t("Current Position"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    if let start = locationManager.recordingStartDate {
                        Label("REC", systemImage: "record.circle")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(formatDuration(context.date.timeIntervalSince(start)))
                                .font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundColor(.white)
                        }
                    } else if locationManager.stoppedDuration > 0 {
                        Text(formatDuration(locationManager.stoppedDuration))
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                panelDivider

                // Main Stats Grid + heading compass on the right
                HStack(spacing: 15) {
                    VStack(spacing: 12) {
                        HStack(spacing: 15) {
                            StatBox(label: t("Speed"), value: formatSpeed(location.effectiveSpeed))
                            StatBox(label: t("Altitude"), value: formatAltitude(location.altitude))
                        }
                        HStack(spacing: 15) {
                            StatBox(label: t("Distance"), value: formatDistance(locationManager.totalDistance))
                            StatBox(label: t("POIs"), value: "\(locationManager.pois.count)")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    headingCompass
                }

                panelDivider

                // Coordinates
                HStack {
                    VStack(alignment: .leading) {
                        Text(t("Latitude"))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                        Text(String(format: "%.6f°", location.coordinate.latitude))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(t("Longitude"))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                        Text(String(format: "%.6f°", location.coordinate.longitude))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                panelDivider

                // GPS signal quality. iOS does not expose satellite counts,
                // so accuracy is the quality proxy: bars + level on the left,
                // horizontal/vertical error on the right.
                HStack {
                    SignalIndicator(accuracy: location.horizontalAccuracy)
                    Text(t(gpsQualityLabel(location.horizontalAccuracy)))
                        .font(.caption.bold())
                        .foregroundColor(gpsQualityColor(location.horizontalAccuracy))
                    Spacer()
                    Text(String(format: "H ±%.0f m  V ±%.0f m", location.horizontalAccuracy, max(location.verticalAccuracy, 0)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
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
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isPanelCompact = true }
            }
    }

    // Compass showing the direction of travel: the dial stays north-up and
    // the arrow rotates to the current GPS course (or compass heading when
    // stationary). Shows "--" until a direction is available.
    private var headingCompass: some View {
        let direction = locationManager.movementDirection
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                Text("N")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
                    .offset(y: -24)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(direction != nil ? .orange : .gray)
                    .rotationEffect(.degrees(direction ?? 0))
            }
            .frame(width: 58, height: 58)

            Text(direction.map { String(format: "%.0f°", $0) } ?? "--")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundColor(.white)
        }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }
    
    // Quality levels keyed to the same accuracy thresholds SignalIndicator
    // uses for its bars.
    private func gpsQualityLabel(_ accuracy: Double) -> String {
        switch accuracy {
        case ..<5: return "Excellent"
        case ..<10: return "Good"
        case ..<30: return "Fair"
        case ..<100: return "Poor"
        default: return "Very Poor"
        }
    }

    private func gpsQualityColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case ..<10: return .green
        case ..<30: return .orange
        default: return .red
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatSpeed(_ metersPerSecond: Double) -> String {
        if useImperialUnits {
            return String(format: "%.1f mph", metersPerSecond * 2.23694)
        }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }

    private func formatAltitude(_ meters: Double) -> String {
        if useImperialUnits {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatDistance(_ meters: Double) -> String {
        if useImperialUnits {
            if meters < 1609.344 {
                return String(format: "%.0f ft", meters * 3.28084)
            }
            return String(format: "%.2f mi", meters / 1609.344)
        }
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
    @AppStorage("appLanguage") private var appLanguage = "en"

    private func t(_ key: String) -> String { L10n.text(key, appLanguage) }

    private var location: CLLocation? { locationManager.location }

    var body: some View {
        NavigationView {
            List {
                if locationManager.accuracyAuthorization == .reducedAccuracy {
                    Section {
                        Label(t("Precise Location is off — accuracy is limited to ~1–2 km."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Button(t("Enable Precise Location")) {
                            locationManager.requestTemporaryFullAccuracy()
                        }
                    }
                }

                if let location = location {
                    Section(t("Signal Quality")) {
                        HStack {
                            Text(t("Accuracy"))
                            Spacer()
                            Text(String(format: "±%.1f m", location.horizontalAccuracy))
                                .foregroundColor(accuracyColor(location.horizontalAccuracy))
                        }
                        
                        HStack {
                            Text(t("Signal Level"))
                            Spacer()
                            SignalIndicator(accuracy: location.horizontalAccuracy)
                        }
                    }
                    
                    Section(t("Detailed Metadata")) {
                        LabeledContent(t("Vertical Accuracy"), value: String(format: "±%.1f m", location.verticalAccuracy))
                        LabeledContent(t("Course"), value: location.course >= 0 ? String(format: "%.1f°", location.course) : "--")
                        LabeledContent(t("Timestamp"), value: location.timestamp.formatted(date: .omitted, time: .standard))
                        
                        if #available(iOS 15.0, *) {
                            LabeledContent(t("Source"), value: location.sourceInformation?.isSimulatedBySoftware == true ? t("Simulated") : t("GPS/Hardware"))
                        }
                    }
                } else {
                    Text(t("No GPS data available"))
                }
            }
            .navigationTitle(t("GPS Status"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("Done")) { dismiss() }
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

struct FilesView: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @State private var files: [URL] = []
    @State private var selected: Set<URL> = []
    @AppStorage("appLanguage") private var appLanguage = "en"

    private func t(_ key: String) -> String { L10n.text(key, appLanguage) }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if files.isEmpty {
                    ContentUnavailableView(t("No Tracks"), systemImage: "folder", description: Text(t("Tracks are saved here automatically when you stop recording.")))
                } else {
                    List {
                        ForEach(files, id: \.self) { url in
                            HStack {
                                Image(systemName: selected.contains(url) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(selected.contains(url) ? .blue : .secondary)
                                Label(url.lastPathComponent, systemImage: "doc.text")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSelection(url) }
                        }
                    }

                    HStack(spacing: 12) {
                        ShareLink(items: Array(selected)) {
                            fileActionLabel(t("Share"), icon: "square.and.arrow.up", color: .blue)
                        }
                        .opacity(selected.isEmpty ? 0.4 : 1)
                        .allowsHitTesting(!selected.isEmpty)

                        Button(action: deleteSelected) {
                            fileActionLabel(t("Delete"), icon: "trash", color: .red)
                        }
                        .disabled(selected.isEmpty)
                        .opacity(selected.isEmpty ? 0.4 : 1)

                        Button(action: mergeSelected) {
                            fileActionLabel(t("Merge"), icon: "arrow.triangle.merge", color: .orange)
                        }
                        .disabled(selected.count < 2)
                        .opacity(selected.count < 2 ? 0.4 : 1)
                    }
                    .padding()
                }
            }
            .navigationTitle(t("Tracks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("Done")) { dismiss() }
                }
            }
        }
        .onAppear { files = locationManager.savedTrackFiles() }
    }

    private func fileActionLabel(_ title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.bold())
        .foregroundColor(.white)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(color)
        .cornerRadius(12)
    }

    private func toggleSelection(_ url: URL) {
        if selected.contains(url) {
            selected.remove(url)
        } else {
            selected.insert(url)
        }
    }

    private func deleteSelected() {
        for url in selected {
            locationManager.deleteTrackFile(url)
        }
        files.removeAll { selected.contains($0) }
        selected.removeAll()
    }

    private func mergeSelected() {
        guard locationManager.mergeTrackFiles(Array(selected)) != nil else { return }
        selected.removeAll()
        files = locationManager.savedTrackFiles()
    }
}

struct SettingsView: View {
    @AppStorage("mapStyle") private var mapStyle = "standard"
    @AppStorage("useImperialUnits") private var useImperialUnits = false
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @AppStorage("appLanguage") private var appLanguage = "en"
    @Environment(\.dismiss) var dismiss

    private func t(_ key: String) -> String { L10n.text(key, appLanguage) }

    var body: some View {
        NavigationView {
            Form {
                Section(t("Map")) {
                    Picker(t("Map Type"), selection: $mapStyle) {
                        Text(t("Standard")).tag("standard")
                        Text(t("Satellite")).tag("satellite")
                    }
                }
                Section(t("Units")) {
                    Toggle(t("Imperial (mi, mph)"), isOn: $useImperialUnits)
                }
                Section(t("Screen")) {
                    Toggle(t("Keep Screen On"), isOn: $keepScreenOn)
                }
                Section(t("Language")) {
                    Picker(t("Language"), selection: $appLanguage) {
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                }
            }
            .navigationTitle(t("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
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
