//
//  ViewModels.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

class UserState: ObservableObject {
    @Published var user: User?
    
    func updateProfilePicture(_ newUrl: String) {
        if var currentUser = user {
            currentUser.profilePictureUrl = newUrl
            user = currentUser
        }
    }
}

class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var currentUrl: URL?
    
    func loadImage(from url: URL) {
        // If we're already loading this URL, don't reload
        if currentUrl == url { return }
        
        currentUrl = url
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data),
                  self.currentUrl == url else { return }
            
            DispatchQueue.main.async {
                self.image = image
            }
        }.resume()
    }
}

struct TimelinePoint: Identifiable {
    let id = UUID()
    let date: Date
    var yPosition: CGFloat = 0
}
