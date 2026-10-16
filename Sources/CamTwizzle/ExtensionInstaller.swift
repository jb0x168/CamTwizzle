import Foundation
import Observation
import Security
import SystemExtensions

/// Activates/deactivates the embedded CamTwizzle Camera system extension.
@MainActor
@Observable
final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    static let shared = ExtensionInstaller()

    enum State: Equatable {
        case unknown, notInstalled, awaitingApproval, active, failed(String), working
    }

    var state: State = .unknown
    var log: [String] = []

    var extensionIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "dev.camtwizzle.CamTwizzle") + ".Camera"
    }

    var extensionURL: URL? {
        let dir = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension == "systemextension" }
    }

    /// Team ID of the running app's signature (nil for ad-hoc / self-signed builds).
    static let teamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    var canInstall: Bool { ExtensionInstaller.teamIdentifier != nil && extensionURL != nil }

    var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    func activate() {
        state = .working
        log.append("Requesting activation of \(extensionIdentifier)…")
        let req = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func deactivate() {
        state = .working
        log.append("Requesting removal…")
        let req = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func refresh() {
        let req = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    // MARK: Delegate

    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated {
            state = .awaitingApproval
            log.append("Waiting for approval in System Settings › General › Login Items & Extensions › Camera Extensions.")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        MainActor.assumeIsolated {
            switch result {
            case .completed:
                state = .active
                log.append("Done.")
            case .willCompleteAfterReboot:
                state = .awaitingApproval
                log.append("Will complete after a restart.")
            @unknown default:
                log.append("Result \(result.rawValue)")
            }
            AppModel.shared.refreshSinks()
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let ns = error as NSError
            var msg = ns.localizedDescription
            if ns.domain == OSSystemExtensionErrorDomain {
                switch OSSystemExtensionError.Code(rawValue: ns.code) {
                case .missingEntitlement: msg = "Missing entitlement — the app must be signed with a Developer Team that has the System Extension capability."
                case .unsupportedParentBundleLocation: msg = "Move CamTwizzle.app to /Applications first."
                case .extensionNotFound: msg = "The camera extension isn't embedded in this build."
                case .codeSignatureInvalid: msg = "Code signature invalid — the extension must be signed by the same Developer Team as the app."
                case .validationFailed: msg = "Validation failed (signing/provisioning profile)."
                case .requestCanceled: msg = "Canceled."
                case .authorizationRequired: msg = "Authorization required."
                default: break
                }
            }
            state = .failed(msg)
            log.append("Failed: \(msg) [\(ns.domain) \(ns.code)]")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        MainActor.assumeIsolated {
            if let p = properties.first(where: { $0.isEnabled }) {
                state = p.isAwaitingUserApproval ? .awaitingApproval : .active
            } else if properties.contains(where: { $0.isAwaitingUserApproval }) {
                state = .awaitingApproval
            } else {
                state = .notInstalled
            }
        }
    }
}
