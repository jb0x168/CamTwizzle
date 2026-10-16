import CoreMediaIO
import Foundation
import os.log

// CamTwizzle Camera — a CoreMediaIO Camera Extension.
//
// Each device exposes a *source* stream (what Photo Booth / Zoom read) and a
// *sink* stream that the CamTwizzle app feeds with rendered frames via the
// CoreMediaIO client API. While no frames arrive, a placeholder card is shown.

let log = OSLog(subsystem: "dev.camtwizzle.camera", category: "extension")

let info = Bundle.main.infoDictionary ?? [:]
let deviceCount = max(1, min(4, (info["CamTwizzleDeviceCount"] as? Int) ?? 1))
let baseName = (info["CamTwizzleDeviceName"] as? String) ?? "CamTwizzle"

let provider = CamTwizzleProvider(deviceCount: deviceCount, baseName: baseName)
CMIOExtensionProvider.startService(provider: provider.provider)
CFRunLoopRun()
