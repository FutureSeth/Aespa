//
//  AespaCoreRecorder.swift
//  
//
//  Created by 이영빈 on 2023/06/02.
//

import UIKit
import Foundation
import AVFoundation

/// Start, stop recording and responsible for notifying the result of recording
class AespaCoreRecorder: NSObject {
    private let core: AespaCoreSession

    /// The caller waiting in `stopRecording()`, resumed exactly once when the file finishes.
    private var stopContinuation: CheckedContinuation<URL, Error>?
    /// A recording that finished before anyone asked to stop it (e.g. the session was
    /// interrupted). Handed to the next `stopRecording()` so it doesn't wait forever.
    private var unclaimedResult: Result<URL, Error>?
    private let stateLock = NSLock()

    init(core: AespaCoreSession) {
        self.core = core
    }

    func run<T: AespaMovieFileOutputProcessing>(processor: T, _ onComplete: @escaping CompletionHandler) {
        core.run(processor, onComplete)
    }
}

extension AespaCoreRecorder {
    func startRecording(
        in filePath: URL,
        _ autoVideoOrientationEnabled: Bool,
        _ onComplete: @escaping CompletionHandler
    ) {
        stateLock.withLock {
            unclaimedResult = nil
        }

        // Read on the caller's (main) queue; the processor runs on the session queue.
        let videoOrientation = autoVideoOrientationEnabled ? UIDevice.current.orientation.toVideoOrientation : nil

        run(processor: StartRecordProcessor(
            filePath: filePath,
            delegate: self,
            videoOrientation: videoOrientation),
            onComplete)
    }
    
    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            enum Claim {
                case alreadyFinished(Result<URL, Error>)
                case alreadyStopping
                case waiting
            }

            // Register before stopping so the delegate callback can't arrive first.
            let claim: Claim = stateLock.withLock {
                if let result = unclaimedResult {
                    unclaimedResult = nil
                    return .alreadyFinished(result)
                }
                if stopContinuation != nil {
                    return .alreadyStopping
                }
                stopContinuation = continuation
                return .waiting
            }

            switch claim {
            case .alreadyFinished(let result):
                continuation.resume(with: result)
            case .alreadyStopping:
                continuation.resume(throwing: AespaError.device(reason: .busy))
            case .waiting:
                run(processor: FinishRecordProcessor()) { [weak self] result in
                    if case .failure(let error) = result {
                        self?.takeStopContinuation()?.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func takeStopContinuation() -> CheckedContinuation<URL, Error>? {
        stateLock.withLock {
            defer { stopContinuation = nil }
            return stopContinuation
        }
    }
}

extension AespaCoreRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Logger.log(message: "Recording started")
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Logger.log(message: "Recording stopped")

        let result: Result<URL, Error>
        if let error {
            Logger.log(error: error)
            result = .failure(error)
        } else {
            result = .success(outputFileURL)
        }

        // Resume whoever is waiting; if nobody asked to stop yet, keep it for the next call.
        let waiting: CheckedContinuation<URL, Error>? = stateLock.withLock {
            if let continuation = stopContinuation {
                stopContinuation = nil
                return continuation
            }
            unclaimedResult = result
            return nil
        }
        waiting?.resume(with: result)
    }
}
