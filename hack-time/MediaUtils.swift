//
//  MediaUtils.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI
import AVFoundation
import UIKit

struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        print("Bundle path: \(Bundle.main.bundlePath)")
        
        guard let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") else {
            print("Could not create URL for video: \(videoName).mp4")
            return view
        }
        
        let player = AVPlayer(url: videoURL)
        player.isMuted = true
        
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.frame = UIScreen.main.bounds
        videoLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(videoLayer)
        
        print("Screen bounds: \(UIScreen.main.bounds)")
        print("Video layer frame: \(videoLayer.frame)")
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main) { _ in
                print("Video reached end, looping...")
                player.seek(to: .zero)
                player.play()
            }
        
        print("Starting video playback...")
        player.play()
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        print("LoopingVideoPlayer view updated")
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    let allowsEditing: Bool
    
    init(completion: @escaping (UIImage?) -> Void, allowsEditing: Bool = false) {
        self.completion = completion
        self.allowsEditing = allowsEditing
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = allowsEditing
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion, allowsEditing: allowsEditing)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        let allowsEditing: Bool
        
        init(completion: @escaping (UIImage?) -> Void, allowsEditing: Bool) {
            self.completion = completion
            self.allowsEditing = allowsEditing
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let key: UIImagePickerController.InfoKey = allowsEditing ? .editedImage : .originalImage
            let image = info[key] as? UIImage
            completion(image)
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
            picker.dismiss(animated: true)
        }
    }
}
