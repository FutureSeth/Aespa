//
//  CapturePhotoProcessor.swift
//  
//
//  Created by 이영빈 on 2023/06/18.
//

import AVFoundation

struct CapturePhotoProcessor: AespaCapturePhotoOutputProcessing {
    let setting: AVCapturePhotoSettings
    let delegate: AVCapturePhotoCaptureDelegate
    /// Resolved by the caller on the main queue; `nil` leaves the connection's orientation alone.
    let videoOrientation: AVCaptureVideoOrientation?

    func process<T>(_ output: T) throws where T: AespaPhotoOutputRepresentable {
        guard let connection = output.getConnection(with: .video) else {
            throw AespaError.session(reason: .cannotFindConnection)
        }
        
        if let videoOrientation {
            connection.orientation(to: videoOrientation)
        }

        output.capturePhoto(with: setting, delegate: delegate)
    }
}
