import CoreNFC
import UIKit

enum Haptics {
    private static let notification = UINotificationFeedbackGenerator()

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.prepare()
        notification.notificationOccurred(type)
    }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }
}

struct ScanOutcome {
    var uid: String?
    var wroteLink: Bool
    var error: String?
}

@Observable
final class NFCTagScanner: NSObject, NFCTagReaderSessionDelegate {
    enum Mode { case read, write }

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    var isScanning = false

    private var session: NFCTagReaderSession?
    private var mode: Mode = .read
    private var completion: ((ScanOutcome) -> Void)?
    private var pendingOutcome: ScanOutcome?

    func scan(mode: Mode, _ completion: @escaping (ScanOutcome) -> Void) {
        self.mode = mode
        self.completion = completion
        pendingOutcome = nil
        guard Self.isAvailable else {
            Haptics.error()
            finish(ScanOutcome(uid: nil, wroteLink: false, error: "NFC isn't available on this device."))
            return
        }
        isScanning = true
        session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self)
        session?.alertMessage = mode == .write ? "Hold near a tag to link it." : "Hold near your tag."
        session?.begin()
    }

    private func finish(_ outcome: ScanOutcome?) {
        isScanning = false
        completion?(outcome ?? ScanOutcome(uid: nil, wroteLink: false, error: nil))
        completion = nil
        session = nil
    }

    private func deliverPending() {
        let outcome = pendingOutcome
        pendingOutcome = nil
        finish(outcome)
    }

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.deliverPending()
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                session.invalidate(errorMessage: "Couldn't read this tag.")
                return
            }
            let identifier: Data?
            let ndefTarget: (any NFCNDEFTag)?
            switch tag {
            case .miFare(let t):
                identifier = t.identifier
                ndefTarget = t
            case .iso7816(let t):
                identifier = t.identifier
                ndefTarget = t
            case .iso15693(let t):
                identifier = t.identifier
                ndefTarget = t
            case .feliCa(let t):
                identifier = t.currentIDm
                ndefTarget = t
            @unknown default:
                identifier = nil
                ndefTarget = nil
            }
            guard let data = identifier, let target = ndefTarget else {
                session.invalidate(errorMessage: "Unsupported tag type.")
                return
            }
            let uid = data.map { String(format: "%02X", $0) }.joined()

            if mode == .read {
                pendingOutcome = ScanOutcome(uid: uid, wroteLink: false, error: nil)
                session.alertMessage = "\(uid.prefix(8))…"
                session.invalidate()
                DispatchQueue.main.async {
                    Haptics.success()
                    self.deliverPending()
                }
                return
            }

            writeLink(to: target, uid: uid, session: session)
        }
    }

    private func writeLink(to target: any NFCNDEFTag, uid: String, session: NFCTagReaderSession) {
        guard let url = URL(string: "remindy://t/\(uid)"),
              let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
            pendingOutcome = ScanOutcome(uid: uid, wroteLink: false, error: "Couldn't prepare the tag link.")
            session.invalidate(errorMessage: "Couldn't prepare the tag link.")
            DispatchQueue.main.async { [weak self] in self?.deliverPending() }
            return
        }
        Task { [weak self] in
            do {
                let (status, _) = try await target.queryNDEFStatus()
                switch status {
                case .readWrite:
                    try await target.writeNDEF(NFCNDEFMessage(records: [payload]))
                    session.alertMessage = "Tag linked."
                    self?.pendingOutcome = ScanOutcome(uid: uid, wroteLink: true, error: nil)
                    session.invalidate()
                    await MainActor.run {
                        Haptics.success()
                        self?.deliverPending()
                    }
                case .readOnly:
                    self?.pendingOutcome = ScanOutcome(
                        uid: uid, wroteLink: false,
                        error: "This tag is read-only, so background taps won't work. It's still linked for in-app scans.")
                    session.invalidate(errorMessage: "This tag is read-only.")
                    await MainActor.run { self?.deliverPending() }
                default:
                    self?.pendingOutcome = ScanOutcome(
                        uid: uid, wroteLink: false,
                        error: "This tag can't store links, so background taps won't work. It's still linked for in-app scans.")
                    session.invalidate(errorMessage: "This tag can't store links.")
                    await MainActor.run { self?.deliverPending() }
                }
            } catch {
                self?.pendingOutcome = ScanOutcome(uid: uid, wroteLink: false, error: "Writing to the tag failed.")
                session.invalidate(errorMessage: "Writing to the tag failed.")
                await MainActor.run { self?.deliverPending() }
            }
        }
    }
}
