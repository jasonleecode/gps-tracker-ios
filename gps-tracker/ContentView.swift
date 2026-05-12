import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSatelliteStatus = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                UserAnnotation()
                
                if locationManager.path.count > 1 {
                    MapPolyline(coordinates: locationManager.path.map { $0.coordinate })
                        .stroke(.blue, lineWidth: 5)
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
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Unified Top-Left Controls
                HStack(spacing: 10) {
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
                        
                        // Share/Export Button
                        if !locationManager.path.isEmpty || !locationManager.pois.isEmpty {
                            let gpxContent = locationManager.exportAsGPX()
                            ShareLink(item: gpxContent, preview: SharePreview("Track.gpx", image: Image(systemName: "map"))) {
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
                    
                    Spacer()
                }
                .padding(.top, 10)
                
                Spacer()
                
                // Action Buttons (Start/Stop & POI)
                HStack(spacing: 20) {
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
                .padding(.horizontal)
                
                // Stats Card
                if let location = locationManager.location {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("Current Position")
                                .font(.headline)
                            Spacer()
                            if locationManager.isRecording {
                                Label("REC", systemImage: "record.circle")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Divider()
                        
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
                        
                        Divider()
                        
                        // Coordinates
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Latitude")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.6f°", location.coordinate.latitude))
                                    .font(.system(.subheadline, design: .monospaced))
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Longitude")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.6f°", location.coordinate.longitude))
                                    .font(.system(.subheadline, design: .monospaced))
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .shadow(color: .black.opacity(0.1), radius: 5)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showSatelliteStatus) {
            SatelliteStatusView(location: locationManager.location)
        }
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
    let location: CLLocation?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
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
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.body.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ContentView()
}
