import CoreLocation
import MapKit
import SwiftUI

struct PlaceSelection: Equatable {
    var latitude: Double
    var longitude: Double
    var name: String
}

struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let initial: PlaceSelection?
    let onConfirm: (PlaceSelection) -> Void

    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var resolvingName = false
    @State private var search = ""
    @State private var completions: [MKLocalSearchCompletion] = []

    @State private var completer = CompleterModel()
    @State private var searchTask: Task<Void, Never>?
    private let geocoder = CLGeocoder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapSection
                searchField
                if !completions.isEmpty {
                    resultsList
                }
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let pin else { return }
                        onConfirm(
                            PlaceSelection(latitude: pin.latitude, longitude: pin.longitude, name: name)
                        )
                        dismiss()
                    }
                    .disabled(pin == nil || name.isEmpty || resolvingName)
                }
            }
            .onAppear(perform: setup)
            .onChange(of: search) { _, newValue in
                completer.queryFragment = newValue
                completions = newValue.trimmingCharacters(in: .whitespaces).isEmpty
                    ? [] : completer.results
            }
        }
    }

    private var mapSection: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let pin {
                    Marker(name.isEmpty ? "Selected place" : name, coordinate: pin)
                        .tint(Color.accentColor)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                dropPin(at: coordinate)
            }
        }
        .overlay(alignment: .bottom) {
            if let pin {
                Label(
                    String(format: "%.4f, %.4f", pin.latitude, pin.longitude),
                    systemImage: "mappin"
                )
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 10)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for a place", text: $search)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !search.isEmpty {
                Button {
                    search = ""
                    completions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var resultsList: some View {
        List(completions, id: \.self) { completion in
            Button {
                select(completion: completion)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(completion.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(completion.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .listStyle(.plain)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 220)
    }

    private func setup() {
        completer.onUpdate = { results in
            completions = Array(results.prefix(6))
        }
        if let initial {
            let center = CLLocationCoordinate2D(latitude: initial.latitude, longitude: initial.longitude)
            pin = center
            name = initial.name
            camera = .camera(MapCamera(centerCoordinate: center, distance: 900))
        } else if let here = LocationReminderStore.shared.currentLocation {
            camera = .camera(MapCamera(centerCoordinate: here.coordinate, distance: 1200))
        } else {
            camera = .automatic
        }
    }

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        pin = coordinate
        completions = []
        search = ""
        resolvingName = true
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
            Task { @MainActor in
                resolvingName = false
                name = placemarks?.first.map(Self.placeName(from:)) ?? Self.coords(coordinate)
            }
        }
    }

    private func select(completion: MKLocalSearchCompletion) {
        searchTask?.cancel()
        searchTask = Task {
            let request = MKLocalSearch.Request(completion: completion)
            let localSearch = MKLocalSearch(request: request)
            guard let response = try? await localSearch.start(),
                  let item = response.mapItems.first else { return }
            let coordinate = item.placemark.coordinate
            let title = item.name ?? completion.title
            guard !Task.isCancelled else { return }
            pin = coordinate
            name = title
            completions = []
            search = title
            withAnimation(reduceMotion ? nil : Motion.reveal) {
                camera = .camera(MapCamera(centerCoordinate: coordinate, distance: 900))
            }
        }
    }

    private static func placeName(from placemark: CLPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !street.isEmpty { return street }
        if let area = placemark.locality ?? placemark.name { return area }
        return coords(placemark.location?.coordinate)
    }

    private static func coords(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "Selected place" }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}

@Observable
final class CompleterModel: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    var results: [MKLocalSearchCompletion] = []
    var onUpdate: (([MKLocalSearchCompletion]) -> Void)?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var queryFragment: String {
        get { completer.queryFragment }
        set { completer.queryFragment = newValue }
    }

    func completer(_ completer: MKLocalSearchCompleter, didUpdateResults results: [MKLocalSearchCompletion]) {
        Task { @MainActor in
            self.results = results
            onUpdate?(results)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            results = []
        }
    }
}
