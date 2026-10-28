//
//  AespaCoreSessionManager.swift
//
//
//  Created by 이영빈 on 2023/06/02.
//

import UIKit
import Combine
import Foundation
import AVFoundation

class AespaCoreSession: AVCaptureSession {
    var option: AespaOption

    /// Owns every session, device, connection and output change. `commitConfiguration()` and
    /// `startRunning()` block until the capture graph is rebuilt, which can take seconds, so
    /// none of this work may run on the main queue.
    private let sessionQueue = DispatchQueue(label: "Aespa.sessionQueue", qos: .userInitiated)

    /// Holds queued work back until `start(_:)` has added the inputs and outputs it needs.
    private let workQueue = OperationQueue()

    init(option: AespaOption) {
        self.option = option

        workQueue.underlyingQueue = sessionQueue
        workQueue.maxConcurrentOperationCount = 1
        workQueue.isSuspended = true
    }

    func run<T: AespaSessionTuning>(_ tuner: T, _ onComplete: @escaping CompletionHandler) {
        enqueue(tuner, onComplete) {
            if tuner.needTransaction { self.beginConfiguration() }
            defer {
                if tuner.needTransaction { self.commitConfiguration() }
            }

            try tuner.tune(self)
        }
    }

    func run<T: AespaDeviceTuning>(_ tuner: T, _ onComplete: @escaping CompletionHandler) {
        enqueue(tuner, onComplete) {
            guard let device = self.videoDeviceInput?.device else {
                throw AespaError.device(reason: .invalid)
            }

            if tuner.needLock { try device.lockForConfiguration() }
            defer {
                if tuner.needLock { device.unlockForConfiguration() }
            }

            try tuner.tune(device)
        }
    }

    func run<T: AespaConnectionTuning>(_ tuner: T, _ onComplete: @escaping CompletionHandler) {
        enqueue(tuner, onComplete) {
            guard let connection = self.connections.first else {
                throw AespaError.session(reason: .cannotFindConnection)
            }

            try tuner.tune(connection)
        }
    }

    func run<T: AespaMovieFileOutputProcessing>(_ processor: T, _ onComplete: @escaping CompletionHandler) {
        enqueue(processor, onComplete) {
            guard let output = self.movieFileOutput else {
                throw AespaError.session(reason: .cannotFindConnection)
            }

            try processor.process(output)
        }
    }

    func run<T: AespaCapturePhotoOutputProcessing>(_ processor: T, _ onComplete: @escaping CompletionHandler) {
        enqueue(processor, onComplete) {
            guard let output = self.photoOutput else {
                throw AespaError.session(reason: .cannotFindConnection)
            }

            try processor.process(output)
        }
    }

    /// Adds the inputs and outputs and starts the session on the session queue, then releases
    /// any work queued in the meantime. `onComplete` is called on the main queue.
    func start(_ onComplete: @escaping CompletionHandler) {
        sessionQueue.async {
            let result: Result<Void, Error>
            do {
                if self.isRunning == false {
                    try self.addMovieInput()
                    try self.addMovieFileOutput()
                    try self.addCapturePhotoOutput()
                    self.startRunning()
                    Logger.log(message: "Session is configured successfully")
                }
                result = .success(())
            } catch {
                Logger.log(error: error, message: "while starting the session")
                result = .failure(error)
            }

            // Release queued work even on failure, so it fails fast instead of waiting forever.
            self.workQueue.isSuspended = false
            DispatchQueue.main.async { onComplete(result) }
        }
    }
}

private extension AespaCoreSession {
    /// Runs `work` serially on the session queue and reports its result once, on the main queue.
    func enqueue(_ owner: Any, _ onComplete: @escaping CompletionHandler, _ work: @escaping () throws -> Void) {
        workQueue.addOperation {
            let result: Result<Void, Error>
            do {
                try work()
                result = .success(())
            } catch {
                Logger.log(error: error, message: "in \(owner)")
                result = .failure(error)
            }

            DispatchQueue.main.async { onComplete(result) }
        }
    }
}
