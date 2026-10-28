//
//  AespaCoreCamera.swift
//
//
//  Created by Young Bin on 2023/06/18.
//

import UIKit
import Foundation
import AVFoundation

/// Capturing a photo and responsible for notifying the result
class AespaCoreCamera: NSObject {
    private let core: AespaCoreSession

    /// One continuation per in-flight capture, keyed by its settings' `uniqueID`, so
    /// overlapping captures each resume exactly once with their own photo.
    private var pendingCaptures: [Int64: CheckedContinuation<AVCapturePhoto, Error>] = [:]
    private let pendingCapturesLock = NSLock()

    init(core: AespaCoreSession) {
        self.core = core
    }
}

extension AespaCoreCamera {
    func capture(
        setting: AVCapturePhotoSettings,
        autoVideoOrientationEnabled: Bool
    ) async throws -> AVCapturePhoto {
        // UIDevice is main-only; the processor runs on the session queue.
        var videoOrientation: AVCaptureVideoOrientation?
        if autoVideoOrientationEnabled {
            videoOrientation = await MainActor.run { UIDevice.current.orientation.toVideoOrientation }
        }
        let processor = CapturePhotoProcessor(setting: setting, delegate: self, videoOrientation: videoOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            // Register before starting the capture so a fast delegate callback can't miss it.
            pendingCapturesLock.withLock {
                pendingCaptures[setting.uniqueID] = continuation
            }

            core.run(processor) { result in
                if case .failure(let error) = result {
                    self.takePendingCapture(for: setting.uniqueID)?.resume(throwing: error)
                }
            }
        }
    }

    private func takePendingCapture(for uniqueID: Int64) -> CheckedContinuation<AVCapturePhoto, Error>? {
        pendingCapturesLock.withLock {
            pendingCaptures.removeValue(forKey: uniqueID)
        }
    }
}

extension AespaCoreCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Logger.log(message: "Photo captured")

        // A capture can deliver more than one photo; the first one resolves it.
        guard let continuation = takePendingCapture(for: photo.resolvedSettings.uniqueID) else {
            return
        }

        if let error {
            Logger.log(error: error)
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: photo)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        // Always the last callback for a capture. If no photo arrived, fail instead of
        // leaving the caller suspended forever.
        guard let continuation = takePendingCapture(for: resolvedSettings.uniqueID) else {
            return
        }

        let failure = error ?? AespaError.file(reason: .unableToFlatten)
        Logger.log(error: failure)
        continuation.resume(throwing: failure)
    }
}
