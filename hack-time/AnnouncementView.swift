//
//  AnnouncementView.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct AnnouncementModalView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authManager: AuthManager
    @State private var newMessage: String = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Announcements")
                .font(.system(size: 24))
                .padding()
            
            Divider()
            
            if let event = authManager.selectedEvent {
                if event.announcements.isEmpty {
                    VStack {
                        Spacer()
                        Text("No announcements yet")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(event.announcements.sorted(by: { $0.timeSent > $1.timeSent })) { announcement in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 16) {
                                        if let pictureUrl = announcement.sender.profilePicture {
                                            AsyncImageView(url: URL(string: pictureUrl)!)
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .frame(width: 44, height: 44)
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Text(announcement.sender.name)
                                        
                                        Text(formatDate(announcement.timeSent))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                    }
                                    
                                    Text(announcement.content)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                
                                if announcement.id != event.announcements.sorted(by: { $0.timeSent > $1.timeSent }).last?.id {
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            } else {
                Text("No event selected")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Message input area
            HStack(alignment: .center, spacing: 8) {
                TextField("Type announcement...", text: $newMessage, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .onSubmit {
                        let trimmedMessage = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedMessage.isEmpty {
                            sendAnnouncement()
                        }
                    }
                    .disabled(isLoading)
                
                Button(action: sendAnnouncement) {
                    if isLoading {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .frame(height: 32)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        .background(Color(UIColor.systemBackground))
    }
    
    private func sendAnnouncement() {
        guard let event = authManager.selectedEvent,
              !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let announcement = try await authManager.createAnnouncement(
                    content: newMessage,
                    eventId: event.id
                )
                
                await MainActor.run {
                    // Update the UI with the new announcement
                    authManager.addAnnouncement(announcement, to: event)
                    
                    // Clear the input field
                    newMessage = ""
                    isFocused = false
                    isLoading = false
                }
            } catch {
                print("Failed to send announcement:", error)
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AsyncImageView: View {
    let url: URL

    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else if isLoading {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            if let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = uiImage
                    self.isLoading = false
                }
            }
        }
        task.resume()
    }
}
