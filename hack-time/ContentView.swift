import SwiftUI
import UIKit
import AVFoundation
import Foundation

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

struct CalendarEvent: Identifiable {
    let id = UUID()
    var title: String
    var startTime: Date
    var endTime: Date
    var color: Color
}

struct EventView: View {
    let event: CalendarEvent
    let dayStartTime: Date
    @State private var isEditing: Bool
    @Binding var events: [CalendarEvent]
    @FocusState private var isFocused: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    // Add these properties
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let notificationFeedback = UINotificationFeedbackGenerator()
    // Remove the separate editableTitle state and use computed property instead
    private var editableTitle: String {
        get {
            event.title
        }
        set {
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index].title = newValue
            }
        }
    }
    init(event: CalendarEvent, dayStartTime: Date, events: Binding<[CalendarEvent]>, isNewEvent: Bool = false) {
        self.event = event
        self.dayStartTime = dayStartTime
        self._events = events
        self._isEditing = State(initialValue: isNewEvent)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("New Event", text: Binding(
                    get: { event.title },
                    set: { newValue in
                        if let index = events.firstIndex(where: { $0.id == event.id }) {
                            events[index].title = newValue
                        }
                    }
                ))
                    .foregroundColor(.white)
                    .font(.system(size: 18))
                    .background(Color.clear)
                    .focused($isFocused)
                    .onSubmit {
                        updateEventTitle()
                    }
                Spacer()
            }
            .onTapGesture {
                isEditing = true
                isFocused = true
            }
            Spacer()
            
            Text(formatEventTime(start: event.startTime, end: event.endTime))
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 14))
        }
        .padding(16)
        .frame(width: 320, height: calculateEventHeight())
        .background(event.color)
        .cornerRadius(16)
        .padding(.vertical, 8)
        .padding(.leading, 16)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    let proposedOffset = value.translation.height
                    let snappedOffset = snapToNearestHour(offset: proposedOffset)
                    
                    if !wouldOverlap(with: snappedOffset) {
                        dragOffset = snappedOffset
                        impactMed.impactOccurred(intensity: 0.5)
                    } else {
                        notificationFeedback.notificationOccurred(.error)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    updateEventTime()
                    dragOffset = 0
                }
        )
        .animation(.interactiveSpring(), value: dragOffset)
        .onAppear {
            if isEditing {
                isFocused = true
            }
        }
    }
    
    private func formatEventTime(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startString = formatter.string(from: start).lowercased()
        let endString = formatter.string(from: end).lowercased()
        return "\(startString) - \(endString)"
    }
    
    private func calculateRelativeTime(_ time: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: dayStartTime, to: time)
        return calendar.date(byAdding: components, to: dayStartTime) ?? time
    }
    
    private func calculateEventHeight() -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: event.startTime, to: event.endTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0 - 16 // Subtract 8px to account for vertical padding
    }

    private func updateEventTitle() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            if events[index].title.isEmpty {
                events.remove(at: index)
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    impact.impactOccurred()
                }
            }
        }
        isEditing = false
        isFocused = false
    }

    private func snapToNearestHour(offset: CGFloat) -> CGFloat {
        let hourHeight: CGFloat = 72.0
        return round(offset / hourHeight) * hourHeight
    }

    private func wouldOverlap(with offset: CGFloat) -> Bool {
        let newStartTime = Calendar.current.date(byAdding: .minute, value: Int(offset / 72.0 * 60), to: event.startTime)!
        let newEndTime = Calendar.current.date(byAdding: .minute, value: Int(offset / 72.0 * 60), to: event.endTime)!

        return events.contains { otherEvent in
            guard otherEvent.id != event.id else { return false }
            return (newStartTime < otherEvent.endTime && newEndTime > otherEvent.startTime)
        }
    }

    private func updateEventTime() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            let minutesToAdd = Int(dragOffset / 72.0 * 60)
            events[index].startTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: event.startTime)!
            events[index].endTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: event.endTime)!
        }
    }
}

struct TimelinePoint: Identifiable {
    let id = UUID()
    let date: Date
    var yPosition: CGFloat = 0
}

// Add this class to handle API calls
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String?
    @Published var isLoading = false
    
    private let baseURL = "https://serenidad.click/hacktime"
    
    func login(email: String, password: String) async throws -> String {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw AuthError.invalidCredentials
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        return result.token
    }
    
    func signup(email: String, password: String, name: String) async throws -> String {
        let url = URL(string: "\(baseURL)/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email, "password": password, "name": name]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 400 {
            throw AuthError.emailInUse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        return result.token
    }
    
    func validateToken(_ token: String) async throws -> User {
        let url = URL(string: "\(baseURL)/auth")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["token": token]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw AuthError.invalidToken
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        return try JSONDecoder().decode(User.self, from: data)
    }
    
    func requestPasswordReset(email: String) async throws {
        let url = URL(string: "\(baseURL)/forgotPasswordRequest")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
    }
    
    func changePassword(email: String, oneTimeCode: String, newPassword: String) async throws {
        let url = URL(string: "\(baseURL)/changePassword")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email, "oneTimeCode": oneTimeCode, "newPassword": newPassword]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 400 {
            throw AuthError.invalidCode
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
    }
}

// Add these models and enums
struct TokenResponse: Codable {
    let token: String
}

struct User: Codable {
    let email: String
    let name: String
    let profilePictureUrl: String?
    let token: String
    
    enum CodingKeys: String, CodingKey {
        case email, name, token
        case profilePictureUrl = "profile_picture_url"
    }
}

enum AuthError: Error {
    case invalidCredentials
    case emailInUse
    case invalidToken
    case invalidResponse
    case serverError
    case invalidCode
}

// Update ContentView to include environment object
struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainContentView()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(authManager) // Add this line to pass authManager down
        .onAppear {
            checkAuth()
        }
    }
    
    private func checkAuth() {
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            authManager.isAuthenticated = false
            return
        }
        
        Task {
            do {
                _ = try await authManager.validateToken(token)
                await MainActor.run {
                    authManager.isAuthenticated = true
                }
            } catch {
                await MainActor.run {
                    authManager.isAuthenticated = false
                    UserDefaults.standard.removeObject(forKey: "authToken")
                }
            }
        }
    }
}

struct MainContentView: View {
    let startTime: Date
    let endTime: Date
    
    @State private var selectedTag: String = "Event"
    let tags = ["Event", "You", "Dieter", "Nila", "Sam", "Dev", "JC", "Lexi"]
    
    @State private var dragOffset: CGFloat = 0
    @State private var previousDragValue: DragGesture.Value?
    
    // Add this property to store the namespace for the ScrollViewReader
    @Namespace private var tagNamespace
    
    // Add this property to control the visibility of events
    @State private var showEvents: Bool = true
    @State private var eventOffset: CGFloat = 0
    
    // Add this function to generate haptic feedback
    private func generateHapticFeedback() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    // Add this state variable in the ContentView struct
    @State private var isAnnouncementModalPresented = false
    
    @State private var timelinePoints: [TimelinePoint] = []
    
    @State private var startTimelinePoint: TimelinePoint?
    @State private var currentTimelinePoint: TimelinePoint?
    
    @State private var events: [CalendarEvent] = []
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    let notificationFeedback = UINotificationFeedbackGenerator()
    
    @State private var isCreatingEvent: Bool = false
    @State private var previewStartTime: Date?
    @State private var previewEndTime: Date?
    
    // Add this property to the ContentView struct
    @State private var lastHourFeedback: Int?
    
    @State private var newEventId: UUID?
    
    // Add this state variable
    @State private var selectedEvent: CalendarEvent?
    
    // Add this state variable
    @State private var showProfileDropdown = false
    
    // Add this property
    @State private var user: User?
    
    init() {
        let calendar = Calendar.current
        let now = Date()
        
        // Set start time to today at 8:00 AM in the device's local time zone
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = 8
        startComponents.minute = 0
        startComponents.second = 0
        self.startTime = calendar.date(from: startComponents)!
        
        // Set end time to 33 hours after start time
        self.endTime = calendar.date(byAdding: .hour, value: 33, to: self.startTime)!
        
        // Add correct events
        let sampleEvents = [
            CalendarEvent(title: "Attendees begin to arrive", 
                          startTime: self.startTime, 
                          endTime: calendar.date(byAdding: .hour, value: 7, to: self.startTime)!, 
                          color: Color(red: 218/255, green: 128/255, blue: 0/255)),
            CalendarEvent(title: "Opening Ceremony", 
                          startTime: calendar.date(byAdding: .hour, value: 7, to: self.startTime)!,
                          endTime: calendar.date(byAdding: .hour, value: 8, to: self.startTime)!,
                          color: Color(red: 2/255, green: 147/255, blue: 212/255)), // 0293D4 in RGB
            CalendarEvent(title: "Dinner + Hacking Begins", 
                          startTime: calendar.date(byAdding: .hour, value: 8, to: self.startTime)!, 
                          endTime: calendar.date(byAdding: .hour, value: 12, to: self.startTime)!, 
                          color: Color(red: 8/255, green: 164/255, blue: 42/255)) // 08A42A in RGB
        ]
        _events = State(initialValue: sampleEvents)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Run Of Show")
                    .font(.largeTitle)
                    .fontWeight(.medium)

                Spacer()

                Button(action: {
                    isAnnouncementModalPresented = true
                }) {
                    Image(systemName: "message.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                }
                .padding(.trailing, 8)

                if let user = user {
                    ProfileImageView(user: user)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                showProfileDropdown.toggle()
                            }
                        }
                }
            }
            .padding()
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .foregroundColor(selectedTag == tag ? .white : Color(red: 89/255, green: 99/255, blue: 110/255))
                                .padding(.horizontal, 12.0)
                                .padding(.vertical, 8.0)
                                .background(selectedTag == tag ? Color.black : Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(red: 89/255, green: 99/255, blue: 110/255), lineWidth: selectedTag == tag ? 0 : 1)
                                )
                                .onTapGesture {
                                    if selectedTag != tag {
                                        selectedTag = tag
                                        generateHapticFeedback()
                                        withAnimation {
                                            proxy.scrollTo(tag, anchor: .center)
                                        }
                                    }
                                }
                                .id(tag)
                        }
                    }
                    .padding([.leading, .bottom, .trailing])
                }
                .onChange(of: selectedTag) { newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            
            
            ScrollView {
                Text("it's hack time you hacker...")
                    .foregroundColor(Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.0))
                    .frame(height: 8)
                ZStack(alignment: .topLeading) {
                    // Timeline
                    VStack(spacing: 0) {
                        ForEach(timelinePoints) { point in
                            VStack {
                                HStack {
                                    VStack(alignment: .leading) {
                                        if shouldShowWeekday(for: point.date) {
                                            Text(formatWeekday(date: point.date))
                                                .font(.system(size: 14))
                                                .foregroundColor(Color(hue: 1.0, saturation: 0.0, brightness: 0.459))
                                                .frame(width: 32, alignment: .leading)
                                        }
                                        
                                        Text(formatTime(date: point.date))
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hue: 1.0, saturation: 0.0, brightness: 0.459))
                                            .frame(width: 42, alignment: .leading)
                                    }
                                    .padding(.leading, 12)
                                    .frame(height: 0, alignment: .leading)
                                    
                                    VStack {
                                        Divider()
                                    }
                                }
                                Spacer()
                            }
                            .frame(height: 72.0)
                        }
                    }
                    
                    // Events
                    if showEvents {
                        ForEach(events.indices, id: \.self) { index in
                            EventView(event: events[index], dayStartTime: startTime, events: $events, isNewEvent: events[index].id == newEventId)
                                .padding(.leading, 42)
                                .offset(y: calculateEventOffset(for: events[index]))
                                .offset(x: eventOffset)
                                .animation(.spring(), value: eventOffset)
                                .onTapGesture {
                                    selectedEvent = events[index]
                                }
                        }
                        .transition(.move(edge: .leading))
                    }
                    
                    // Event Preview
                    if isCreatingEvent, let start = previewStartTime, let end = previewEndTime, selectedTag == "Event" {
                        EventPreviewView(startTime: start, endTime: end, dayStartTime: startTime)
                            .padding(.leading, 42)
                            .offset(y: calculateEventOffset(for: CalendarEvent(title: "", startTime: start, endTime: end, color: .clear)))
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { print("Tap") }
                            .gesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .sequenced(before: DragGesture(minimumDistance: 0))
                                    .onChanged { value in
                                        if selectedTag == "Event" {
                                            switch value {
                                            case .first(true):
                                                break
                                            case .second(true, let drag):
                                                if let location = drag?.location {
                                                    if self.startTimelinePoint == nil {
                                                        self.impactHeavy.impactOccurred()
                                                        self.startTimelinePoint = findNearestTimelinePoint(to: location.y)
                                                        self.previewStartTime = self.startTimelinePoint?.date
                                                        self.isCreatingEvent = true
                                                        self.lastHourFeedback = Calendar.current.component(.hour, from: self.previewStartTime ?? Date())
                                                    }
                                                    self.currentTimelinePoint = findNearestTimelinePoint(to: location.y, roundUp: true)
                                                    self.previewEndTime = self.currentTimelinePoint?.date
                                                    
                                                    // Provide haptic feedback for each hour change (up or down)
                                                    if let endTime = self.previewEndTime,
                                                       let lastFeedback = self.lastHourFeedback {
                                                        let currentHour = Calendar.current.component(.hour, from: endTime)
                                                        if currentHour != lastFeedback {
                                                            self.impactMed.impactOccurred(intensity: 0.5)
                                                            self.lastHourFeedback = currentHour
                                                        }
                                                    }
                                                }
                                            default:
                                                break
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        if selectedTag == "Event" {
                                            if let startPoint = self.startTimelinePoint,
                                               let endPoint = self.currentTimelinePoint {
                                                print("Start timeline point: \(formatDate(startPoint.date))\n" +
                                                      "Final timeline point: \(formatDate(endPoint.date))")
                                                createCalendarEvent(start: startPoint.date, end: endPoint.date)
                                            }
                                        }
                                        self.startTimelinePoint = nil
                                        self.currentTimelinePoint = nil
                                        self.isCreatingEvent = false
                                        self.previewStartTime = nil
                                        self.previewEndTime = nil
                                        self.lastHourFeedback = nil
                                    }
                            )
                    }
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if let previous = previousDragValue {
                        let delta = value.translation.width - previous.translation.width
                        dragOffset += delta
                        
                        // Update eventOffset for animation
                        if selectedTag == "Event" {
                            eventOffset = dragOffset
                        }
                    }
                    previousDragValue = value
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if dragOffset > threshold {
                        selectPreviousTag()
                    } else if dragOffset < -threshold {
                        selectNextTag()
                    } else {
                        // Reset eventOffset if the drag didn't result in a tag change
                        eventOffset = 0
                    }
                    dragOffset = 0
                    previousDragValue = nil
                }
        )
        .onChange(of: selectedTag) { newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                showEvents = (newValue == "Event")
                if !showEvents {
                    eventOffset = -UIScreen.main.bounds.width
                } else {
                    eventOffset = 0
                }
            }
        }
        // Add this modifier at the end of the VStack in the body
        .sheet(isPresented: $isAnnouncementModalPresented) {
            AnnouncementModalView(isPresented: $isAnnouncementModalPresented)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailModalView(event: event, events: $events)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            timelinePoints = hoursBetween(start: startTime, end: endTime)
        }
        .overlay(
            Group {
                if showProfileDropdown {
                    ProfileDropdownView(isPresented: $showProfileDropdown)
                }
            }
        )
        .task {
            await loadUserData()
        }
    }

    private func selectNextTag() {
        if let currentIndex = tags.firstIndex(of: selectedTag),
           currentIndex < tags.count - 1 {
            selectedTag = tags[currentIndex + 1]
            generateHapticFeedback()
            animateEventTransition(direction: .trailing)
        }
    }

    private func selectPreviousTag() {
        if let currentIndex = tags.firstIndex(of: selectedTag),
           currentIndex > 0 {
            selectedTag = tags[currentIndex - 1]
            generateHapticFeedback()
            animateEventTransition(direction: .leading)
        }
    }

    private func animateEventTransition(direction: Edge) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if selectedTag == "Event" {
                eventOffset = 0
            } else {
                eventOffset = direction == .leading ? UIScreen.main.bounds.width : -UIScreen.main.bounds.width
            }
        }
    }

    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatWeekday(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private func shouldShowWeekday(for date: Date) -> Bool {
        let calendar = Calendar.current
        if date == startTime {
            return true
        }
        let previousHour = calendar.date(byAdding: .hour, value: -1, to: date)!
        return !calendar.isDate(date, inSameDayAs: previousHour)
    }
    
    private func hoursBetween(start: Date, end: Date) -> [TimelinePoint] {
        var points: [TimelinePoint] = []
        var currentDate = start
        var yPosition: CGFloat = 0
        
        while currentDate <= end {
            let point = TimelinePoint(date: currentDate, yPosition: yPosition)
            points.append(point)
            currentDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
            yPosition += 72.0
        }
        
        return points
    }
    
    private func findNearestTimelinePoint(to yPosition: CGFloat, roundUp: Bool = false) -> TimelinePoint? {
        if roundUp {
            return timelinePoints.first { $0.yPosition >= yPosition }
        } else {
            return timelinePoints.last { $0.yPosition <= yPosition }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter.string(from: date)
    }
    
    private func calculateEventOffset(for event: CalendarEvent) -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: startTime, to: event.startTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0
    }
    
    private func createCalendarEvent(start: Date, end: Date) {
        // Check for overlaps
        if events.contains(where: { event in
            (start >= event.startTime && start < event.endTime) ||
            (end > event.startTime && end <= event.endTime) ||
            (start <= event.startTime && end >= event.endTime)
        }) {
            print("Cannot create event: Overlaps with existing event")
            notificationFeedback.notificationOccurred(.error)
            return
        }
        
        // Create new CalendarEvent
        let newEvent = CalendarEvent(
            title: "",
            startTime: start,
            endTime: end,
            color: Color(red: 2/255, green: 147/255, blue: 212/255)
        )
        
        // Add to events array
        events.append(newEvent)
        newEventId = newEvent.id
        
        print("Event created: \(formatDate(start)) - \(formatDate(end))")
        impactHeavy.impactOccurred()
    }

    private func loadUserData() async {
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            do {
                let authManager = AuthManager()
                let userData = try await authManager.validateToken(token)
                await MainActor.run {
                    self.user = userData
                }
            } catch {
                print("Error loading user data:", error)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Modify the AnnouncementModalView structure
struct AnnouncementModalView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            // Title
            Text("Announcements")
                .font(.system(size: 24))
                .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        HStack(spacing: 16){
                            AsyncImageView(url: URL(string: "https://thispersondoesnotexist.com")!)                            
                            Text("Alex")
                            Text("12:23 PM")
                                .opacity(0.5)
                            Spacer()
                        }
                        Text("Hey everyone, we are pushing the dinner to 5PM because several flights have been delayed a couple of hours and transportation is taking longer than expected")
                            .opacity(0.8)
                    }
                    .padding()
                    Text("Announcement content goes here")
                        .foregroundColor(Color(hue: 1.0, saturation: 0.131, brightness: 0.812, opacity: 0.0))
                        .padding(.horizontal)
                    
                    
                    // Add more content as needed
                }
            }
            
            Spacer()
        }
        .background(Color(UIColor.systemBackground))
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct EventPreviewView: View {
    let startTime: Date
    let endTime: Date
    let dayStartTime: Date
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Unnamed")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
                Spacer()
            }
            Spacer()
            
            Text(formatEventTime(start: startTime, end: endTime))
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 14))
        }
        .padding(16)
        .frame(width: 320, height: calculateEventHeight())
        .background(Color(red: 2/255, green: 147/255, blue: 212/255).opacity(0.5))
        .cornerRadius(16)
        .padding(.vertical, 8)
        .padding(.leading, 16)
    }
    
    private func formatEventTime(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startString = formatter.string(from: start).lowercased()
        let endString = formatter.string(from: end).lowercased()
        return "\(startString) - \(endString)"
    }
    
    private func calculateEventHeight() -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: startTime, to: endTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0 - 16
    }
}

// Add this new struct for the event detail modal
struct EventDetailModalView: View {
    @State private var selectedColor: Color
    let event: CalendarEvent
    @Binding var events: [CalendarEvent]
    @Environment(\.presentationMode) var presentationMode
    
    // Add this property to generate haptic feedback
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let notificationFeedback = UINotificationFeedbackGenerator()
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    // Add this state variable for the delete confirmation alert
    @State private var showDeleteConfirmation = false
    
    @State private var editableTitle: String
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFocused: Bool
    
    @State private var isEditingStartTime: Bool = false
    @State private var isEditingEndTime: Bool = false
    @FocusState private var focusedField: TimeField?
    
    @State private var currentStartTime: Date
    @State private var currentEndTime: Date
    
    enum TimeField {
        case start
        case end
    }
    
    init(event: CalendarEvent, events: Binding<[CalendarEvent]>) {
        self.event = event
        self._events = events
        self._selectedColor = State(initialValue: event.color)
        self._editableTitle = State(initialValue: event.title)
        self._currentStartTime = State(initialValue: event.startTime)
        self._currentEndTime = State(initialValue: event.endTime)
    }
    
    let colorOptions: [Color] = [
        Color(red: 218/255, green: 128/255, blue: 0/255),   // #DA8000
        Color(red: 2/255, green: 147/255, blue: 212/255),   // #0293D4
        Color(red: 8/255, green: 164/255, blue: 42/255),    // #08A42A
        Color(red: 142/255, green: 8/255, blue: 164/255),   // #8E08A4
        Color(red: 190/255, green: 58/255, blue: 44/255),   // #BE3A2C
        Color(red: 89/255, green: 89/255, blue: 89/255)     // #595959
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if isEditingTitle {
                    TextField("Event Title", text: $editableTitle)
                        .font(.system(size: 24))
                        .focused($isTitleFocused)
                            .onSubmit {
                            updateEventTitle()
                        }
                        .submitLabel(.done)
                            } else {
                    Text(editableTitle)
                        .font(.system(size: 24))
                        .onTapGesture {
                            isEditingTitle = true
                            isTitleFocused = true
                        }
                }
                Spacer()
                            Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                        HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                        
                        HStack(spacing: 4) {
                            Button(action: {
                                isEditingStartTime = true
                                focusedField = .start
                            }) {
                                Text(formatTime(date: currentStartTime))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(6)
                            }
                            
                            Text("-")
                            
                            Button(action: {
                                isEditingEndTime = true
                                focusedField = .end
                            }) {
                                Text(formatTime(date: currentEndTime))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(6)
                            }
                        }
                        .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .sheet(isPresented: $isEditingStartTime) {
                        TimePickerView(
                            selectedDate: Binding(
                                get: { currentStartTime },
                                set: { newDate in
                                    currentStartTime = newDate
                                    updateEventTimes()
                                }
                            ),
                            isPresented: $isEditingStartTime
                        )
                        .presentationDetents([.height(300)])
                    }
                    .sheet(isPresented: $isEditingEndTime) {
                        TimePickerView(
                            selectedDate: Binding(
                                get: { currentEndTime },
                                set: { newDate in
                                    currentEndTime = newDate
                                    updateEventTimes()
                                }
                            ),
                            isPresented: $isEditingEndTime
                        )
                        .presentationDetents([.height(300)])
                    }
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                        Text(formatEventDate(date: event.startTime))
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                            Text("Event Color")
                        }
                        
                        HStack(spacing: 15) {
                            ForEach(colorOptions, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: selectedColor == color ? 40 : 30, height: selectedColor == color ? 40 : 30)
                                    .opacity(selectedColor == color ? 1 : 0.5)
                                    .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)) {
                                            selectedColor = color
                                            updateEventColor()
                                        }
                                        // Generate haptic feedback
                                        impactMed.impactOccurred()
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Add more event details as needed
                }
                .padding(.vertical)
                }
                
                Spacer()
            }
        .background(Color(UIColor.systemBackground))
        .edgesIgnoringSafeArea(.bottom)
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Event"),
                message: Text("Are you sure you want to delete this event?"),
                primaryButton: .destructive(Text("Delete")) {
                    deleteEvent()
                },
                secondaryButton: .cancel()
            )
        }
        .onChange(of: isTitleFocused) { focused in
            if !focused {
                updateEventTitle()
            }
        }
    }
    
    private func formatEventTime(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startString = formatter.string(from: start).lowercased()
        let endString = formatter.string(from: end).lowercased()
        return "\(startString) - \(endString)"
    }
    
    private func formatEventDate(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func updateEventColor() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index].color = selectedColor
        }
    }
    
    private func deleteEvent() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events.remove(at: index)
            impactMed.impactOccurred()
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func updateEventTitle() {
        let newTitle = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            var updatedEvent = events[index]
            updatedEvent.title = newTitle
            events[index] = updatedEvent
        }
        isEditingTitle = false
        isTitleFocused = false
    }
    
    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).lowercased()
    }
    
    private func updateEventTimes() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            // Check if duration is 0 or negative
            if currentEndTime <= currentStartTime {
                notificationFeedback.notificationOccurred(.error)
                // Reset to previous valid times
                currentStartTime = events[index].startTime
                currentEndTime = events[index].endTime
                return
            }
            
            // Check for overlaps with other events
            let wouldOverlap = events.contains { otherEvent in
                guard otherEvent.id != event.id else { return false }
                return (currentStartTime < otherEvent.endTime && 
                        currentEndTime > otherEvent.startTime)
            }
            
            if wouldOverlap {
                notificationFeedback.notificationOccurred(.error)
                // Reset to previous valid times
                currentStartTime = events[index].startTime
                currentEndTime = events[index].endTime
                return
            }
            
            // If we get here, the times are valid
            var updatedEvent = events[index]
            updatedEvent.startTime = currentStartTime
            updatedEvent.endTime = currentEndTime
            events[index] = updatedEvent
            impactMed.impactOccurred(intensity: 0.5)
        }
    }
}

// Add this new view for the time picker
struct TimePickerView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            DatePicker(
                "Select Time",
                selection: $selectedDate,
                displayedComponents: [.hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .navigationBarItems(
                trailing: Button("Done") {
                    isPresented = false
                }
            )
            .padding()
        }
    }
}

// Update ProfileDropdownView to handle logout
struct ProfileDropdownView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authManager: AuthManager // Add this line
    
    var body: some View {
        ZStack {
            // Overlay that closes dropdown when tapped
            if isPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isPresented = false
                        }
                    }
            }
            
            // Dropdown menu
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    UserDefaults.standard.removeObject(forKey: "authToken")
                    authManager.isAuthenticated = false // Add this line
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
            .background(Color(UIColor.systemBackground))
            .cornerRadius(8)
            .shadow(radius: 4)
            .offset(x: -12, y: 60) // Adjusted offset
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

struct OnboardingView: View {
    @State private var showLogin = false
    @State private var showSignup = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .edgesIgnoringSafeArea(.all)
                
                LoopingVideoPlayer(videoName: "background")
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Build Time")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 2)
                    Spacer()
                    VStack(spacing: 12){
                        Button(action: {
                            showLogin = true
                        }, label: {
                            Text("Login")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .font(.system(size: 18))
                                .fontWeight(.medium)
                        })
                        .padding(.horizontal, 16)
                        
                        Button(action: {
                            showSignup = true
                        }, label: {
                            Text("Signup")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                                .font(.system(size: 18))
                                .fontWeight(.medium)
                        })
                        .padding(.horizontal, 16)
                    }
                }
                .navigationDestination(isPresented: $showLogin) {
                    LoginView()
                }
                .navigationDestination(isPresented: $showSignup) {
                    SignupView()
                }
            }
        }
    }
}

// Update LoginView to use the environment object
struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager // Add this line
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showForgotPassword = false
    
    @FocusState private var focusedField: LoginField?
    
    enum LoginField {
        case email
        case password
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Welcome Back")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .foregroundColor(.gray)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                                .foregroundColor(.gray)
                            HStack {
                                if showPassword {
                                TextField("Enter your password", text: $password)
                                    .textContentType(.password)
                                    .submitLabel(.done)
                                } else {
                                SecureField("Enter your password", text: $password)
                                    .textContentType(.password)
                                    .submitLabel(.done)
                                }
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                            handleLogin()
                                }
                        }
                    }
                    .padding(.horizontal, 24)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: handleLogin) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Login")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                
                Button(action: {
                    showForgotPassword = true
                }) {
                    Text("Forgot Password?")
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
        }
        .onAppear {
            // Delay focus slightly to ensure view is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .email
        }
    }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    private func handleLogin() {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let token = try await authManager.login(email: email, password: password)
                await MainActor.run {
                    UserDefaults.standard.set(token, forKey: "authToken")
                    authManager.isAuthenticated = true // Add this line
                    dismiss()
                }
            } catch AuthError.invalidCredentials {
                errorMessage = "Invalid email or password"
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
}

// Update SignupView to use the environment object
struct SignupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager // Add this line
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var name: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    @FocusState private var focusedField: SignupField?
    
    enum SignupField {
        case name
        case email
        case password
        case confirmPassword
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Create Account")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .foregroundColor(.gray)
                    TextField("Enter your name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .email
                        }
                }
                .padding(.horizontal, 24)

                
                VStack(alignment: .leading, spacing: 20) {
                    // Add name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .foregroundColor(.gray)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .foregroundColor(.gray)
                        HStack {
                            if showPassword {
                                TextField("Enter your password", text: $password)
                                    .textContentType(.password)
                            } else {
                                SecureField("Enter your password", text: $password)
                                    .textContentType(.password)
                            }
                            
                            Button(action: {
                                showPassword.toggle()
                            }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .confirmPassword
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .foregroundColor(.gray)
                        HStack {
                            if showConfirmPassword {
                                TextField("Confirm your password", text: $confirmPassword)
                                    .textContentType(.password)
                            } else {
                                SecureField("Confirm your password", text: $confirmPassword)
                                    .textContentType(.password)
                            }
                            
                            Button(action: {
                                showConfirmPassword.toggle()
                            }) {
                                Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.join)
                        .onSubmit {
                            handleSignup()
                        }
                    }
                }
                .padding(.horizontal, 24)

                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: handleSignup) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign Up")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                
                Button(action: {
                    // Handle forgot password
                    print("Forgot password tapped")
                }) {
                    Text("Forgot Password?")
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
        }
        .onAppear {
            // Delay focus slightly to ensure view is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .email
            }
        }
    }
    
    private func handleSignup() {
        guard !email.isEmpty && !password.isEmpty && !name.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let token = try await authManager.signup(email: email, password: password, name: name)
                await MainActor.run {
                    UserDefaults.standard.set(token, forKey: "authToken")
                    authManager.isAuthenticated = true // Add this line
                    dismiss()
                }
            } catch AuthError.emailInUse {
                errorMessage = "Email is already in use"
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
}

// Add this new struct for video playback
struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // Debug: Print the bundle path
        print("Bundle path: \(Bundle.main.bundlePath)")
        
        // Try to get the URL directly
        guard let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") else {
            print("Could not create URL for video: \(videoName).mp4")
            return view
        }
        
        
        // Create player
        let player = AVPlayer(url: videoURL)
        player.isMuted = true
        
        // Create video layer
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.frame = UIScreen.main.bounds
        videoLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(videoLayer)
        
        // Debug: Print frame
        print("Screen bounds: \(UIScreen.main.bounds)")
        print("Video layer frame: \(videoLayer.frame)")
        
        // Set up looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main) { _ in
                print("Video reached end, looping...")
                player.seek(to: .zero)
                player.play()
            }
        
        // Start playback
        print("Starting video playback...")
        player.play()
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Debug: Print when view updates
        print("LoopingVideoPlayer view updated")
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    @State private var email: String = ""
    @State private var oneTimeCode: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var codeSent = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email
        case code
        case password
        case confirmPassword
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(codeSent ? "Reset Password" : "Forgot Password")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                if !codeSent {
                    // Email input view
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .foregroundColor(.gray)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Code and new password view
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Code")
                                .foregroundColor(.gray)
                            TextField("Enter the code sent to your email", text: $oneTimeCode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .code)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .foregroundColor(.gray)
                            HStack {
                                if showPassword {
                                    TextField("Enter new password", text: $newPassword)
                                } else {
                                    SecureField("Enter new password", text: $newPassword)
                                }
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($focusedField, equals: .password)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .confirmPassword
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .foregroundColor(.gray)
                            HStack {
                                if showPassword {
                                    TextField("Confirm new password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm new password", text: $confirmPassword)
                                }
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($focusedField, equals: .confirmPassword)
                            .submitLabel(.done)
                            .onSubmit {
                                handlePasswordReset()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: codeSent ? handlePasswordReset : handleCodeRequest) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(codeSent ? "Reset Password" : "Send Code")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                
                Spacer()
            }
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            })
        }
        .onAppear {
            focusedField = .email
        }
    }
    
    private func handleCodeRequest() {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.requestPasswordReset(email: email)
                await MainActor.run {
                    codeSent = true
                    focusedField = .code
                }
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
    
    private func handlePasswordReset() {
        guard !oneTimeCode.isEmpty else {
            errorMessage = "Please enter the code"
            return
        }
        
        guard !newPassword.isEmpty else {
            errorMessage = "Please enter a new password"
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.changePassword(email: email, oneTimeCode: oneTimeCode, newPassword: newPassword)
                await MainActor.run {
                    dismiss()
                }
            } catch AuthError.invalidCode {
                errorMessage = "Invalid code"
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
}

struct ProfileImageView: View {
    let user: User
    let size: CGFloat = 44
    
    var body: some View {
        Group {
            if let profileUrl = user.profilePictureUrl,
               let url = URL(string: profileUrl) {
                AsyncImageView(url: url)
            } else {
                // Fallback to circle with initial
                Circle()
                    .fill(Color(red: 220/255, green: 220/255, blue: 220/255)) // Lighter grey background
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(user.name.prefix(1)).uppercased())
                            .foregroundColor(Color(red: 180/255, green: 180/255, blue: 180/255)) // Lighter grey text
                            .font(.system(size: size * 0.5, weight: .regular)) // Regular and uppercase text
                    )
            }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.light)  // Add this line

}
