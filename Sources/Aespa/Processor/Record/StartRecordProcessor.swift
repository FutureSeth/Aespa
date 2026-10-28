//
//  RecordingStarter.swift
//  
//
//  Created by 이영빈 on 2023/06/02.
//

import AVFoundation

struct StartRecordProcessor: AespaMovieFileOutputProcessing {
    let filePath: URL
    let delegate: AVCaptureFileOutputRecordingDelegate
    /// Resolved by the caller on the main queue; `nil` leaves the connection's orientation alone.
    let videoOrientation: AVCaptureVideoOrientation?

    func process<T: AespaFileOutputRepresentable>(_ output: T) throws {
        guard let connection = output.getConnection(with: .video) else {
            throw AespaError.session(reason: .cannotFindConnection)
        }
        
        if let videoOrientation {
            connection.orientation(to: videoOrientation)
        }

        output.startRecording(to: filePath, recordingDelegate: delegate)
    }
}
