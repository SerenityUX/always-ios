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
    @State private var showCustomDeleteAlert = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var alertType: AlertType?
    
    enum AlertType: Identifiable {
        case profileError(String)
        case deleteConfirmation
        case deleteError(String)
        
        var id: String {
            switch self {
            case .profileError:
                return "profileError"
            case .deleteConfirmation:
                return "deleteConfirmation"
            case .deleteError:
                return "deleteError"
            }
        }
    }
    
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
                    showCustomDeleteAlert = true
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.minus")
                        Text("Delete Account")
                    }
                    .foregroundColor(.red)
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
            
            if showCustomDeleteAlert {
                DeleteAccountAlert(
                    isPresented: $showCustomDeleteAlert,
                    confirmationText: $deleteConfirmationText,
                    onDelete: deleteAccount
                )
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(completion: handleImageSelection, allowsEditing: true)
        }
        .sheet(isPresented: $showEventSelection) {
            EventSelectionView()
        }
        .alert(item: $alertType) { type in
            switch type {
            case .profileError(let message):
                Alert(
                    title: Text("Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .deleteConfirmation:
                Alert(
                    title: Text("Error"),
                    message: Text("Unexpected alert type"),
                    dismissButton: .default(Text("OK"))
                )
            case .deleteError(let message):
                Alert(
                    title: Text("Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
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
                    alertType = .profileError("Failed to update profile picture. Please try again.")
                }
            }
        }
    }
    
    private func deleteAccount() {
        isDeletingAccount = true
        
        Task {
            do {
                try await authManager.deleteAccount()
                await MainActor.run {
                    isDeletingAccount = false
                    isPresented = false
                    authManager.isAuthenticated = false
                    authManager.currentUser = nil
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    alertType = .deleteError(error.localizedDescription)
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
    @State private var selectedTimezone = "PST"
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Initialize default times
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let impactMed = UIImpactFeedbackGenerator(style: .medium)
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        
        // Set up default times (8 AM to 9 PM)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        
        // Set default start time (8 AM)
        components.hour = 8
        components.minute = 0
        let defaultStart = calendar.date(from: components) ?? now
        
        // Set default end time (9 PM)
        components.hour = 21
        components.minute = 0
        let defaultEnd = calendar.date(from: components) ?? now
        
        // Initialize state properties
        self._startDate = State(initialValue: defaultStart)
        self._endDate = State(initialValue: defaultEnd)
        self._startTime = State(initialValue: defaultStart)
        self._endTime = State(initialValue: defaultEnd)
    }
    
    private func roundToHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        components.minute = 0
        return calendar.date(from: components) ?? date
    }
    
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
                        .onChange(of: startTime) { newTime in
                            startTime = roundToHour(newTime)
                        }
                }
                
                Section(header: Text("End (UTC)")) {
                    DatePicker("Date", selection: $endDate, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                    DatePicker("Time", selection: $endTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                        .onChange(of: endTime) { newTime in
                            endTime = roundToHour(newTime)
                        }
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
        
        // Get start date components
        let startDateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let startTimeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        
        // Get end date components
        let endDateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        let endTimeComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        // Combine date and time components for start
        var finalStartComponents = DateComponents()
        finalStartComponents.year = startDateComponents.year
        finalStartComponents.month = startDateComponents.month
        finalStartComponents.day = startDateComponents.day
        finalStartComponents.hour = startTimeComponents.hour
        finalStartComponents.minute = startTimeComponents.minute
        finalStartComponents.timeZone = TimeZone(identifier: "UTC")
        
        // Combine date and time components for end
        var finalEndComponents = DateComponents()
        finalEndComponents.year = endDateComponents.year
        finalEndComponents.month = endDateComponents.month
        finalEndComponents.day = endDateComponents.day
        finalEndComponents.hour = endTimeComponents.hour
        finalEndComponents.minute = endTimeComponents.minute
        finalEndComponents.timeZone = TimeZone(identifier: "UTC")
        
        guard let finalStartTime = calendar.date(from: finalStartComponents),
              let finalEndTime = calendar.date(from: finalEndComponents) else {
            errorMessage = "Invalid date/time combination"
            return
        }
        
        // Validate that end time is after start time
        if finalEndTime <= finalStartTime {
            errorMessage = "End time must be after start time"
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

struct DeleteAccountAlert: View {
    @Binding var isPresented: Bool
    @Binding var confirmationText: String
    let onDelete: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 20) {
                Text("Delete Account")
                    .font(.headline)
                
                Text("This action cannot be undone. All your data will be permanently deleted. Type 'DELETE ACCOUNT' to confirm.")
                    .multilineTextAlignment(.center)
                
                TextField("Type 'DELETE ACCOUNT' to confirm", text: $confirmationText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        confirmationText = ""
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Delete") {
                        if confirmationText == "DELETE ACCOUNT" {
                            onDelete()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(confirmationText != "DELETE ACCOUNT")
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 10)
            .padding(40)
        }
    }
}
