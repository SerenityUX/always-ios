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
    @State private var showingCreateEvent = false
    @State private var showDeleteConfirmation = false
    @State private var eventToDelete: (String, Event)? = nil
    @State private var errorMessage: String?
    @State private var showError = false
    
    let notificationFeedback = UINotificationFeedbackGenerator()
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                eventToDelete = (eventId, event)
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    showingCreateEvent = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Event")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding()
                }
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("Select Event")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventView(isPresented: $showingCreateEvent)
            }
            .alert("Delete Event", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                Text("Are you sure you want to delete '\(eventToDelete?.1.title ?? "")'? This action cannot be undone.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    private func deleteEvent() {
        guard let (eventId, _) = eventToDelete else { return }
        
        Task {
            do {
                try await authManager.deleteEvent(eventId: eventId)
                await MainActor.run {
                    impactMed.impactOccurred()
                    if authManager.currentUser?.events.isEmpty ?? true {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    notificationFeedback.notificationOccurred(.error)
                }
            }
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

struct CreateEventView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedTimezone = "PST"
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let impactMed = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Event Title", text: $title)
                }
                
                Section(header: Text("Start (UTC)")) {
                    DatePicker("Date", selection: $startDate, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                    DatePicker("Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                }
                
                Section(header: Text("End (UTC)")) {
                    DatePicker("Date", selection: $endDate, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                    DatePicker("Time", selection: $endTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                }

                Section(header: Text("Event Timezone")) {
                    Picker("Timezone", selection: $selectedTimezone) {
                        ForEach(Array(commonTimezones.keys).sorted(), id: \.self) { key in
                            Text("\(key) - \(commonTimezones[key] ?? "")")
                                .tag(key)
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Create Event")
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Create") {
                    createEvent()
                }
                .disabled(title.isEmpty || isLoading)
            )
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }
    
    private func createEvent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")! // Force UTC timezone
        
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let startTimeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        let endTimeComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        var finalStartComponents = DateComponents()
        finalStartComponents.year = startComponents.year
        finalStartComponents.month = startComponents.month
        finalStartComponents.day = startComponents.day
        finalStartComponents.hour = startTimeComponents.hour
        finalStartComponents.minute = startTimeComponents.minute
        
        var finalEndComponents = DateComponents()
        finalEndComponents.year = endComponents.year
        finalEndComponents.month = endComponents.month
        finalEndComponents.day = endComponents.day
        finalEndComponents.hour = endTimeComponents.hour
        finalEndComponents.minute = endTimeComponents.minute
        
        guard let finalStartTime = calendar.date(from: finalStartComponents),
              let finalEndTime = calendar.date(from: finalEndComponents) else {
            errorMessage = "Invalid date/time combination"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let _ = try await authManager.createEvent(
                    title: title,
                    startTime: finalStartTime,
                    endTime: finalEndTime,
                    timezone: selectedTimezone
                )
                
                await MainActor.run {
                    impactMed.impactOccurred()
                    isLoading = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create event: \(error.localizedDescription)"
                    isLoading = false
                    notificationFeedback.notificationOccurred(.error)
                }
            }
        }
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

let commonTimezones = [
    "PST": "Pacific Time",
    "MST": "Mountain Time",
    "CST": "Central Time",
    "EST": "Eastern Time",
    "GMT": "Greenwich Mean Time",
    "UTC": "Coordinated Universal Time"
]
