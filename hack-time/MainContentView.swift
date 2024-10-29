//
//  MainContentView.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct MainContentView: View {
    let startTime: Date
    let endTime: Date
    
    @State private var selectedTag: String = "Event"
    
    var tags: [String] {
        var dynamicTags = ["Event", "You"]
        
        if let firstEvent = authManager.currentUser?.events.first?.value {
            let teamMemberNames = firstEvent.teamMembers.map { $0.name }
            dynamicTags.append(contentsOf: teamMemberNames)
        }
        
        return dynamicTags
    }
    
    var filteredEvents: [CalendarEvent] {
        guard let event = currentEvent else { return [] }
        
        switch selectedTag {
        case "Event":
            return events
        case "You":
            guard let currentUserEmail = authManager.currentUser?.email else { return [] }
            return events.filter { calendarEvent in
                // Find matching task for this calendar event
                event.tasks.first { task in
                    // Match task time with calendar event time
                    task.startTime == calendarEvent.startTime &&
                    task.endTime == calendarEvent.endTime &&
                    // Check if current user is assigned to this task
                    task.assignedTo.contains { $0.email == currentUserEmail }
                } != nil
            }
        default:
            // Filter by selected team member name
            return events.filter { calendarEvent in
                // Find matching task for this calendar event
                event.tasks.first { task in
                    // Match task time with calendar event time
                    task.startTime == calendarEvent.startTime &&
                    task.endTime == calendarEvent.endTime &&
                    // Check if selected team member is assigned to this task
                    task.assignedTo.contains { $0.name == selectedTag }
                } != nil
            }
        }
    }
    
    var filteredTasks: [EventTask] {
        guard let firstEvent = authManager.currentUser?.events.first?.value else { return [] }

        switch selectedTag {
        case "Event":
            return firstEvent.tasks
        case "You":
            return firstEvent.tasks.filter { task in
                task.assignedTo.contains { user in
                    user.email == authManager.currentUser?.email
                }
            }
        default:
            // Filter by selected team member name
            return firstEvent.tasks.filter { task in
                task.assignedTo.contains { user in
                    user.name == selectedTag
                }
            }
        }
    }
    
    func getFilteredTasks(forEmail email: String?) -> [EventTask] {
    guard let email = email,
          let firstEvent = authManager.currentUser?.events.first?.value else { return [] }
    
    return firstEvent.tasksForUser(email: email)
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var previousDragValue: DragGesture.Value?
    @Namespace private var tagNamespace
    @State private var showEvents: Bool = true
    @State private var eventOffset: CGFloat = 0
    @State private var isAnnouncementModalPresented = false
    @State private var timelinePoints: [TimelinePoint] = []
    @State private var startTimelinePoint: TimelinePoint?
    @State private var currentTimelinePoint: TimelinePoint?
    @State private var events: [CalendarEvent] = []
    @State private var isCreatingEvent: Bool = false
    @State private var previewStartTime: Date?
    @State private var previewEndTime: Date?
    @State private var lastHourFeedback: Int?
    @State private var newEventId: UUID?
    @State private var selectedEvent: CalendarEvent?
    @State private var showProfileDropdown = false
    @State private var user: User?
    
    @State private var previousEvents: [CalendarEvent] = []
    @State private var isAnimatingTransition = false
    @State private var transitionOffset: CGFloat = 0
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    let notificationFeedback = UINotificationFeedbackGenerator()
    
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var userState = UserState()
    
    init(initialEvents: [CalendarEvent] = []) {
        let calendar = Calendar.current
        let now = Date()
        
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = 8
        startComponents.minute = 0
        startComponents.second = 0
        self.startTime = calendar.date(from: startComponents)!
        
        self.endTime = calendar.date(byAdding: .hour, value: 33, to: self.startTime)!
        
        if !initialEvents.isEmpty {
            _events = State(initialValue: initialEvents)
        } else {
            let sampleEvents = [
                CalendarEvent(title: "Create your first calendar event... (delete this one)",
                             startTime: self.startTime,
                             endTime: calendar.date(byAdding: .hour, value: 0, to: self.startTime)!,
                             color: Color(red: 218/255, green: 128/255, blue: 0/255))
            ]
            _events = State(initialValue: sampleEvents)
        }
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

                if let user = userState.user {
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
                                    let userEmail: String? = {
                                        switch tag {
                                        case "You":
                                            return authManager.currentUser?.email
                                        case "Event":
                                            return nil
                                        default:
                                            // Find team member's email by their name
                                            return currentEvent?.teamMembers.first(where: { $0.name == tag })?.email
                                        }
                                    }()
                                    
                                    if let email = userEmail {
                                        let tasks = getFilteredTasks(forEmail: email)
                                        print("Tasks for \(tag):", tasks)
                                    }
                                    
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
                    
                    if showEvents {
                        ForEach(filteredEvents.indices, id: \.self) { index in
                            EventView(event: filteredEvents[index], dayStartTime: startTime, events: $events, isNewEvent: filteredEvents[index].id == newEventId)
                                .padding(.leading, 42)
                                .offset(y: calculateEventOffset(for: filteredEvents[index]))
                                .offset(x: eventOffset)
                                .animation(.spring(), value: eventOffset)
                                .onTapGesture {
                                    selectedEvent = filteredEvents[index]
                                }
                        }
                        .transition(.move(edge: .leading))
                    }
                    
                    if isCreatingEvent, let start = previewStartTime, let end = previewEndTime, selectedTag == "Event" {
                        EventPreviewView(startTime: start, endTime: end, dayStartTime: startTime)
                            .padding(.leading, 42)
                            .offset(y: calculateEventOffset(for: CalendarEvent(title: "", startTime: start, endTime: end, color: .clear)))
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
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
                        eventOffset = 0
                    }
                    dragOffset = 0
                    previousDragValue = nil
                }
        )
        .onChange(of: selectedTag) { newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                showEvents = (newValue == "Event")
                if !showEvents {
                    eventOffset = -UIScreen.main.bounds.width
                } else {
                    eventOffset = 0
                }
            }
        }
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
                    ProfileDropdownView(
                        isPresented: $showProfileDropdown,
                        userState: userState
                    )
                }
            }
        )
        .task {
            loadUserData()
        }
    }

    private func selectNextTag() {
        if let currentIndex = tags.firstIndex(of: selectedTag),
           currentIndex < tags.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTag = tags[currentIndex + 1]
                generateHapticFeedback()
                animateEventTransition(direction: .trailing)
            }
        }
    }

    private func selectPreviousTag() {
        if let currentIndex = tags.firstIndex(of: selectedTag),
           currentIndex > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTag = tags[currentIndex - 1]
                generateHapticFeedback()
                animateEventTransition(direction: .leading)
            }
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

    private func generateHapticFeedback() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
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
    
    private func calculateEventOffset(for event: CalendarEvent) -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: startTime, to: event.startTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0
    }
    
    private func createCalendarEvent(start: Date, end: Date) {
        guard let eventId = authManager.currentUser?.events.first?.key else {
            print("No event ID found")
            return
        }
        
        let calendarEventId = UUID().uuidString
        print("Generated calendar event ID:", calendarEventId)

        let r: Double = 2
        let g: Double = 147
        let b: Double = 212
        
        let eventColor = Color(
            red: r/255.0,
            green: g/255.0,
            blue: b/255.0
        )
        let newEvent = CalendarEvent(
            id: UUID(uuidString: calendarEventId)!,
            title: "",
            startTime: start,
            endTime: end,
            color: eventColor
        )
        
        let colorString = "\(Int(r)),\(Int(g)),\(Int(b))"
        
        Task {
            do {
                let createdEvent = try await authManager.createCalendarEvent(
                    eventId: eventId,
                    calendarEventId: calendarEventId,
                    title: newEvent.title,
                    startTime: start,
                    endTime: end,
                    color: colorString
                )
                
                print("Successfully created event with ID:", createdEvent.id)
                
                let color = createdEvent.color.split(separator: ",").map { Int($0) ?? 0 }
                let uiColor = Color(
                    red: CGFloat(color[0])/255.0,
                    green: CGFloat(color[1])/255.0,
                    blue: CGFloat(color[2])/255.0
                )
                
                let calendarEvent = CalendarEvent(
                    id: UUID(uuidString: createdEvent.id)!,
                    title: createdEvent.title,
                    startTime: createdEvent.startTime,
                    endTime: createdEvent.endTime,
                    color: uiColor
                )
                
                await MainActor.run {
                    events.append(calendarEvent)
                    newEventId = calendarEvent.id
                    impactHeavy.impactOccurred()
                }
            } catch {
                print("Failed to create calendar event:")
                print("Error details:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
    }

    private func loadUserData() {
        guard let token = UserDefaults.standard.string(forKey: "authToken") else { return }
        
        Task {
            do {
                let userData = try await authManager.validateToken(token)
                await MainActor.run {
                    userState.user = userData
                }
            } catch {
                print("Failed to load user data:", error)
            }
        }
    }

    var currentEvent: Event? {
        authManager.currentUser?.events.first?.value
    }
}

struct TaskView: View {
    let task: EventTask
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(task.title)
                .font(.headline)
            Text(task.description)
                .font(.subheadline)
                .foregroundColor(.gray)
            HStack {
                ForEach(task.assignedTo, id: \.email) { user in
                    Text(user.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}
