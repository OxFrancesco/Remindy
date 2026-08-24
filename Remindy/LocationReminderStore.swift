import CoreLocation
import SwiftData
import UIKit
import UserNotifications

@MainActor
@Observable
final class LocationReminderStore: NSObject, CLLocationManagerDelegate {
    static let shared = LocationReminderStore()
    static let maxRegions = 20

    enum Status: Equatable {
        case idle
        case denied
        case monitoring(Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var container: ModelContainer?

    private override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    func attach(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        reconcileNow()
    }

    func requestPermissions() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    var currentLocation: CLLocation? { manager.location }

    func reconcile(with tasks: [Reminder]) {
        let desired = tasks.filter(\.needsPlaceWatch)
        apply(desired: desired)
    }

    func reconcileNow() {
        guard let container else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.parent == nil }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        reconcile(with: all)
    }

    private func apply(desired: [Reminder]) {
        let wanted = Dictionary(
            uniqueKeysWithValues: desired.compactMap { task in
                task.regionID.map { ($0, task) }
            }
        )

        for region in manager.monitoredRegions where wanted[region.identifier] == nil {
            manager.stopMonitoring(for: region)
        }

        var started = 0
        for (id, task) in wanted {
            if manager.monitoredRegions.contains(where: { $0.identifier == id }) { continue }
            guard manager.monitoredRegions.count < Self.maxRegions else {
                status = .failed("Location limit reached (\(Self.maxRegions) places max).")
                break
            }
            guard let latitude = task.latitude, let longitude = task.longitude else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                radius: max(50, task.radiusMeters),
                identifier: id
            )
            region.notifyOnEntry = task.placeTrigger == .onEntry
            region.notifyOnExit = task.placeTrigger == .onExit
            manager.startMonitoring(for: region)
            started += 1
        }

        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .denied, .restricted:
            status = .denied
        default:
            status = .monitoring(manager.monitoredRegions.count)
        }
    }

    func stopAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        status = .idle
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            self.reconcileNow()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        deliver(region: region, arrived: true)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        deliver(region: region, arrived: false)
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        Task { @MainActor in
            self.status = .failed(error.localizedDescription)
        }
    }

    nonisolated private func deliver(region: CLRegion, arrived: Bool) {
        Task { @MainActor in
            guard let container = self.container else { return }
            let context = ModelContext(container)
            let id = region.identifier
            let descriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { $0.regionID == id }
            )
            guard let task = (try? context.fetch(descriptor))?.first, !task.isArchived else { return }
            await Self.postAlarm(
                title: task.title,
                note: task.note,
                placeName: task.placeName,
                arrived: arrived
            )
        }
    }

    nonisolated private static func postAlarm(
        title: String,
        note: String,
        placeName: String,
        arrived: Bool
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(arrived ? "Arriving at" : "Leaving") \(placeName).\(note.isEmpty ? "" : " \(note)")"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
