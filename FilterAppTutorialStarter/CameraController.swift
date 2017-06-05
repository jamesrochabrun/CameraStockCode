//
//  CameraController.swift
//  FilterAppTutorialStarter
//
//  Created by James Rochabrun on 6/5/17.
//  Copyright © 2017 James Rochabrun. All rights reserved.
//

//REFERENCE: http://www.appcoda.com/avfoundation-swift-guide/

import Foundation
import UIKit
import AVFoundation

//MARK: Properties
class CameraController: NSObject {
    
    //session
    var captureSession: AVCaptureSession?
    //device
    var frontCamera: AVCaptureDevice?
    var rearCamera: AVCaptureDevice?
    //inputs
    var currentCameraPosition: CameraPosition?
    var frontCameraInput: AVCaptureDeviceInput?
    var rearCameraInput: AVCaptureDeviceInput?
    //output
    var photoOutput: AVCapturePhotoOutput?
    
    //preview layer
    var previewLayer: AVCaptureVideoPreviewLayer?
    //toggle flash default
    var flashMode = AVCaptureFlashMode.off
    //capture photo completion
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?

}

//MARK: Configuration
extension CameraController {
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        
        //MARK: Step 1 Configure Capture session
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
        }
        
        //MARK: Step 2 Configure device
        func configureCaptureDevices() throws {
            
            //1
            let session = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaTypeVideo, position: .unspecified)
            guard let cameras = (session?.devices.flatMap { $0 }), !cameras.isEmpty else {
                throw CameraControllerError.noCamerasAvailable
            }
            //2
            for camera in cameras {
                if camera.position == .front {
                    self.frontCamera = camera
                }
                
                if camera.position == .back {
                    self.rearCamera = camera
                    
                    try camera.lockForConfiguration()
                    camera.focusMode = .continuousAutoFocus
                    camera.unlockForConfiguration()
                }
            }
        }
        
        //MARK: Step 3 create input using the capture device
        func configureDeviceInputs() throws {
            //3
            guard let captureSession = self.captureSession else {
                throw CameraControllerError.captureSessionIsMissing
            }
            //4
            if let rearCamera = self.rearCamera {
                
                self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                if captureSession.canAddInput(self.rearCameraInput!) {
                    captureSession.addInput(self.rearCameraInput!)
                }
                self.currentCameraPosition = .rear
                
            } else if let frontCamera = self.frontCamera {
                
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                if captureSession.canAddInput(self.frontCameraInput!) {
                    captureSession.addInput(self.frontCameraInput!)
                } else {
                    throw CameraControllerError.inputsAreInvalid
                }
                self.currentCameraPosition = .front
                
            } else {
                throw CameraControllerError.noCamerasAvailable
            }
        }
        
        //MARK: Step 4 Configuring a photo output object to process captured images.
        func configurePhotoOutput() throws {
            
            guard let captureSession = self.captureSession else {
                throw CameraControllerError.captureSessionIsMissing
            }
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecJPEG])], completionHandler: nil)
            
            if captureSession.canAddOutput(self.photoOutput) {
                captureSession.addOutput(self.photoOutput)
            }
            //MARK: Start capture Session
            captureSession.startRunning()
        }
        
        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput()
            }
            catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                return
            }
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
}

//MARK: Main actions Camera
extension CameraController {
    
    //display "video preview" in view
    func displayPreview(on view: UIView) throws {
        
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    //Switching cameras in AV Foundation is a pretty easy task. We just need to remove the capture input for the existing camera and add a new capture input for the camera we want to switch to
    func switchCameras() throws {
        
        //5
        guard let currentCameraPosition = currentCameraPosition, let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }
        //6
        captureSession.beginConfiguration()

        func switchToFrontCamera() throws {
            
            guard let inputs = captureSession.inputs as? [AVCaptureInput], let rearCameraInput = self.rearCameraInput, inputs.contains(rearCameraInput),
                let frontCamera = self.frontCamera else {
                    throw CameraControllerError.invalidOperation
            }
            
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            captureSession.removeInput(rearCameraInput)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                
                captureSession.addInput(self.frontCameraInput!)
                self.currentCameraPosition = .front
            } else {
                throw CameraControllerError.invalidOperation
            }
        }
        
        func switchToRearCamera() throws {
            
            guard let inputs = captureSession.inputs as? [AVCaptureInput], let frontCameraInput = self.frontCameraInput, inputs.contains(frontCameraInput),
                let rearCamera = self.rearCamera else {
                    throw CameraControllerError.invalidOperation
            }
            
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            captureSession.removeInput(frontCameraInput)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                self.currentCameraPosition = .rear
            } else {
                throw CameraControllerError.invalidOperation
            }
        }
        
        //7 This switch statement calls either switchToRearCamera or switchToFrontCamera, depending on which camera is currently active.
        switch currentCameraPosition {
        case .front:
            try switchToRearCamera()
        case .rear:
            try switchToFrontCamera()
        }
        
        //8
        captureSession.commitConfiguration()
    }
    
    //Capture Image
    func captureImage(completion: @escaping (UIImage?, Error?) ->()) {
        
        guard let captureSession = captureSession, captureSession.isRunning else {
            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode
        
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
}

//MARK: Delegate methods
extension CameraController: AVCapturePhotoCaptureDelegate {
    
    public func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?,
                        resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Swift.Error?) {
       
        if let error = error {
            
            self.photoCaptureCompletionBlock?(nil, error)
        } else if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil),
            let image = UIImage(data: data) {
            
            self.photoCaptureCompletionBlock?(image, nil)
            
        } else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
    
}

//MARK: Handling errors & checking states
extension CameraController {
    
    enum CameraControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    public enum CameraPosition {
        case front
        case rear
    }
}
