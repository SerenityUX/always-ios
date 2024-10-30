//
//  ProfileViews.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct ProfileImageView: View {
    @StateObject private var imageLoader = ImageLoader()
    let user: User
    let size: CGFloat = 44
    
    var body: some View {
        Group {
            if let image = imageLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Fallback to circle with initial
                Circle()
                    .fill(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(user.name.prefix(1)).uppercased())
                            .foregroundColor(Color(red: 180/255, green: 180/255, blue: 180/255))
                            .font(.system(size: size * 0.5, weight: .regular))
                    )
            }
        }
        .onChange(of: user.profilePictureUrl) { newUrl in
            if let urlString = newUrl,
               let url = URL(string: urlString) {
                imageLoader.loadImage(from: url)
            } else {
                imageLoader.image = nil
            }
        }
        .onAppear {
            if let urlString = user.profilePictureUrl,
               let url = URL(string: urlString) {
                imageLoader.loadImage(from: url)
            }
        }
    }
}

struct ProfileDropdownView: View {
    @Binding var isPresented: Bool
    @ObservedObject var userState: UserState
    @EnvironmentObject var authManager: AuthManager
    @State private var showImagePicker = false
    @State private var showEventSelection = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isPresented = false
                        }
                    }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("Update Avatar")
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                
                Divider()
                
                Button(action: {
                    showEventSelection = true
                }) {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Change Events")
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                
                Divider()
                
                Button(action: {
                    UserDefaults.standard.removeObject(forKey: "authToken")
                    authManager.isAuthenticated = false
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 200)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(8)
            .shadow(radius: 4)
            .offset(x: -12, y: 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(completion: handleImageSelection, allowsEditing: true)
        }
        .sheet(isPresented: $showEventSelection) {
            EventSelectionView()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleImageSelection(_ image: UIImage?) {
        guard let image = image,
              let imageData = image.jpegData(compressionQuality: 0.7),
              let token = UserDefaults.standard.string(forKey: "authToken") else {
            return
        }
        
        Task {
            do {
                let newProfileUrl = try await authManager.uploadProfilePicture(imageData: imageData, token: token)
                await MainActor.run {
                    userState.updateProfilePicture(newProfileUrl)
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to update profile picture. Please try again."
                    showError = true
                }
            }
        }
    }
}

struct EventSelectionView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if let events = authManager.currentUser?.events {
                    ForEach(Array(events), id: \.key) { eventId, event in
                        Button(action: {
                            authManager.selectedEventId = eventId
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(event.title)
                                        .font(.headline)
                                    Text(formatEventDate(event.startTime))
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                if eventId == authManager.selectedEventId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Event")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatEventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

struct ProfileViews_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample user for preview
        let sampleUser = User(
            email: "test@example.com",
            name: "John Doe",
            profilePictureUrl: nil,
            token: "sample-token",
            events: [:]
        )
        
        Group {
            ProfileImageView(user: sampleUser)
            ProfileDropdownView(
                isPresented: .constant(true),
                userState: UserState()
            )
            .environmentObject(AuthManager())
        }
    }
}
