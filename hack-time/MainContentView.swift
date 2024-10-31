//
//  MainContentView.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct NoEventsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showCreateEventModal = false
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 12) {
                Spacer()
                Text("You are not a part of any events yet...")
                    .font(.body)
                    .multilineTextAlignment(.center)

                
                Text("Create an event or ask an organizer to add you to their event")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()

                HStack(spacing: 16) {
                    Button(action: {
                        if let email = authManager.currentUser?.email {
                            let message = "Hey! I joined HackTime but I have not been added to the event yet. Please invite me with my email \(email) to the event."
                            let urlString = "sms:&body=\(message)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: urlString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }) {
                        Text("Ask for Invite")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                    }
                    
                    Button(action: {
                        showCreateEventModal = true
                    }) {
                        Text("Create Event")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding(.bottom, 16)
                .padding()
            }
            
            Spacer()
        }
        .sheet(isPresented: $showCreateEventModal) {
            CreateEventView(isPresented: $showCreateEventModal)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct MainContentView: View {
    @State var startTime: Date
    @State var endTime: Date
    
    @State private var selectedTag: String = "Event"
    
    var tags: [String] {
        var dynamicTags = ["Event", "You"]
        
        if let event = authManager.selectedEvent {
            let teamMemberNames = event.teamMembers.map { $0.name }
            dynamicTags.append(contentsOf: teamMemberNames)
        }
        
        dynamicTags.append("invite")
        
        return dynamicTags
    }
    
    @State private var forceUpdate: Bool = false
    
    var filteredEvents: [CalendarEvent] {
        guard let event = authManager.selectedEvent else { return [] }
        
        // Force the computed property to update when forceUpdate changes
        _ = forceUpdate
        
        // Convert API events to CalendarEvents
        let calendarEvents = event.calendarEvents.map(convertAPIEventToCalendarEvent)
        
        switch selectedTag {
        case "Event":
            return calendarEvents
        case "You":
            guard let currentUserEmail = authManager.currentUser?.email else { return [] }
            return calendarEvents.filter { calendarEvent in
                event.tasks.contains { task in
                    task.startTime == calendarEvent.startTime &&
                    task.endTime == calendarEvent.endTime &&
                    task.assignedTo.contains { $0.email == currentUserEmail }
                }
            }
        default:
            return calendarEvents.filter { calendarEvent in
                event.tasks.contains { task in
                    task.startTime == calendarEvent.startTime &&
                    task.endTime == calendarEvent.endTime &&
                    task.assignedTo.contains { $0.name == selectedTag }
                }
            }
        }
    }
    
    var filteredTasks: [EventTask] {
        guard let event = authManager.selectedEvent else { return [] }

        // Filter tasks for the current event first
        let eventTasks = event.tasks

        switch selectedTag {
        case "Event":
            return eventTasks
        case "You":
            return eventTasks.filter { task in
                task.assignedTo.contains { user in
                    user.email == authManager.currentUser?.email
                }
            }
        default:
            // Filter by selected team member name
            return eventTasks.filter { task in
                task.assignedTo.contains { user in
                    user.name == selectedTag
                }
            }
        }
    }
    
    func getFilteredTasks(forEmail email: String?) -> [EventTask] {
        guard let email = email,
              let event = authManager.selectedEvent else { return [] }
        
        return event.tasksForUser(email: email)
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
    
    @State private var taskOffset: CGFloat = 0
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    let notificationFeedback = UINotificationFeedbackGenerator()
    
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var userState = UserState()
    
    @State private var proxy: ScrollViewProxy?
    
    @State private var isCreatingTask: Bool = false
    @State private var taskPreviewStart: Date?
    @State private var taskPreviewEnd: Date?
    
    @State private var editingTaskId: String?
    @State private var editingTaskTitle: String = ""
    @FocusState private var isTaskTitleFocused: Bool
    
    @State private var showInviteModal = false
    
    init(initialEvents: [CalendarEvent] = []) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        let now = Date()
        
        // Start with default times
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = 8
        startComponents.minute = 0
        startComponents.second = 0
        startComponents.timeZone = TimeZone(abbreviation: "UTC")  // Force UTC
        let defaultStart = calendar.date(from: startComponents)!
        let defaultEnd = calendar.date(byAdding: .hour, value: 24, to: defaultStart)!
        
        // Initialize @State properties
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: defaultEnd)
        
        if !initialEvents.isEmpty {
            _events = State(initialValue: initialEvents)
        } else {
            let sampleEvents = [
                CalendarEvent(title: "Create your first calendar event... (delete this one)",
                             startTime: defaultStart,
                             endTime: calendar.date(byAdding: .hour, value: 1, to: defaultStart)!,
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

                // Only show announcements button if user has events
                if !(authManager.currentUser?.events.isEmpty ?? true) {
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
                }

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
            
            // Check if user has any events
            if authManager.currentUser?.events.isEmpty ?? true {
                NoEventsView()
                    .padding(.top, 40)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(tags, id: \.self) { tag in
                                if tag == "invite" {
                                    // Special invite button
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("Add")
                                    }
                                    .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                                    .padding(.horizontal, 12.0)
                                    .padding(.vertical, 8.0)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(red: 89/255, green: 99/255, blue: 110/255), lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        showInviteModal = true
                                        generateHapticFeedback()
                                    }
                                    .id(tag)
                                } else {
                                    // Regular tag button (unchanged)
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
                                            withAnimation {
                                                selectedTag = tag
                                                scrollProxy.scrollTo(tag, anchor: .center)
                                            }
                                            generateHapticFeedback()
                                        }
                                        .id(tag)
                                }
                            }
                        }
                        .padding([.leading, .bottom, .trailing])
                    }
                    .onAppear {
                        proxy = scrollProxy
                    }
                    .onChange(of: selectedTag) { newValue in
                        let direction = getTagDirection(from: selectedTag, to: newValue)
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if newValue == "Event" {
                                eventOffset = 0
                                taskOffset = direction == .leading ? -UIScreen.main.bounds.width : UIScreen.main.bounds.width
                            } else if selectedTag == "Event" {
                                eventOffset = direction == .leading ? UIScreen.main.bounds.width : -UIScreen.main.bounds.width
                                taskOffset = 0
                            } else {
                                // Transitioning between team members
                                taskOffset = 0
                                let tempOffset = direction == .leading ? UIScreen.main.bounds.width : -UIScreen.main.bounds.width
                                withAnimation(.easeInOut(duration: 0.01)) {
                                    taskOffset = -tempOffset
                                }
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    taskOffset = 0
                                }
                            }
                        }
                    }
                }
                
                ScrollView {
                    Text("it's hack time you hacker...")
                        .foregroundColor(Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.0))
                        .frame(height: 8)
                    
                    ZStack(alignment: .topLeading) {
                        // Gesture layer for events
                        if selectedTag == "Event" {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { print("Tap") }
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.5)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { value in
                                            switch value {
                                            case .first(true):
                                                impactHeavy.impactOccurred()
                                            case .second(true, let drag):
                                                if let location = drag?.location {
                                                    if startTimelinePoint == nil {
                                                        startTimelinePoint = findNearestTimelinePoint(to: location.y)
                                                        previewStartTime = startTimelinePoint?.date
                                                        isCreatingEvent = true
                                                        lastHourFeedback = Calendar.current.component(.hour, from: previewStartTime ?? Date())
                                                    }
                                                    currentTimelinePoint = findNearestTimelinePoint(to: location.y, roundUp: true)
                                                    previewEndTime = currentTimelinePoint?.date
                                                    
                                                    if let endTime = previewEndTime,
                                                       let lastFeedback = lastHourFeedback {
                                                        let currentHour = Calendar.current.component(.hour, from: endTime)
                                                        if currentHour != lastFeedback {
                                                            impactMed.impactOccurred(intensity: 0.5)
                                                            lastHourFeedback = currentHour
                                                        }
                                                    }
                                                }
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { _ in
                                            if let startPoint = startTimelinePoint,
                                               let endPoint = currentTimelinePoint {
                                                createCalendarEvent(start: startPoint.date, end: endPoint.date)
                                            }
                                            startTimelinePoint = nil
                                            currentTimelinePoint = nil
                                            isCreatingEvent = false
                                            previewStartTime = nil
                                            previewEndTime = nil
                                            lastHourFeedback = nil
                                        }
                                )
                                .allowsHitTesting(true)
                        } else {
                            // Gesture layer for tasks
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { print("Tap") }
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.5)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { value in
                                            switch value {
                                            case .first(true):
                                                impactHeavy.impactOccurred()
                                            case .second(true, let drag):
                                                if let location = drag?.location {
                                                    if startTimelinePoint == nil {
                                                        startTimelinePoint = findNearestTimelinePoint(to: location.y)
                                                        taskPreviewStart = startTimelinePoint?.date
                                                        isCreatingTask = true
                                                        lastHourFeedback = Calendar.current.component(.hour, from: taskPreviewStart ?? Date())
                                                    }
                                                    currentTimelinePoint = findNearestTimelinePoint(to: location.y, roundUp: true)
                                                    taskPreviewEnd = currentTimelinePoint?.date
                                                    
                                                    if let endTime = taskPreviewEnd,
                                                       let lastFeedback = lastHourFeedback {
                                                        let currentHour = Calendar.current.component(.hour, from: endTime)
                                                        if currentHour != lastFeedback {
                                                            impactMed.impactOccurred(intensity: 0.5)
                                                            lastHourFeedback = currentHour
                                                        }
                                                    }
                                                }
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { _ in
                                            if let startPoint = startTimelinePoint,
                                               let endPoint = currentTimelinePoint,
                                               let eventId = authManager.selectedEventId {
                                                
                                                let assigneeEmail = selectedTag == "You" ?
                                                    authManager.currentUser?.email :
                                                    authManager.selectedEvent?.teamMembers.first { $0.name == selectedTag }?.email
                                                
                                                if let email = assigneeEmail {
                                                    createTask(eventId: eventId, startTime: startPoint.date, endTime: endPoint.date, assignee: email)
                                                }
                                            }
                                            startTimelinePoint = nil
                                            currentTimelinePoint = nil
                                            isCreatingTask = false
                                            taskPreviewStart = nil
                                            taskPreviewEnd = nil
                                            lastHourFeedback = nil
                                        }
                                )
                                .allowsHitTesting(true)
                        }
                        
                        // Timeline base layer
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
                        .frame(minHeight: UIScreen.main.bounds.height)
                        
                        // Events layer (move to front)
                        if showEvents {
                            ForEach(tags, id: \.self) { tag in
                                Group {
                                    if tag == "Event" {
                                        // Events view
                                        ForEach(filteredEvents.indices, id: \.self) { index in
                                            EventView(event: filteredEvents[index], dayStartTime: startTime, events: $events, isNewEvent: filteredEvents[index].id == newEventId)
                                                .padding(.leading, 42)
                                                .offset(y: calculateEventOffset(for: filteredEvents[index]))
                                                .offset(x: selectedTag == "Event" ? eventOffset : (
                                                    tags.firstIndex(of: "Event")! < tags.firstIndex(of: selectedTag)! ? 
                                                    -UIScreen.main.bounds.width : UIScreen.main.bounds.width
                                                ))
                                                .animation(.spring(), value: eventOffset)
                                                .onTapGesture {
                                                    selectedEvent = filteredEvents[index]
                                                }
                                                .zIndex(1)
                                        }
                                    } else {
                                        // Tasks view for each tag
                                        let tasks = getTasksForTag(tag: tag)
                                        
                                        ForEach(tasks ?? [], id: \.id) { task in
                                            createTaskView(task: task, tag: tag)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Event Preview layer (keep on top)
                        if isCreatingEvent, let start = previewStartTime, let end = previewEndTime, selectedTag == "Event" {
                            EventPreviewView(startTime: start, endTime: end, dayStartTime: startTime)
                                .padding(.leading, 42)
                                .offset(y: calculateEventOffset(for: CalendarEvent(title: "", startTime: start, endTime: end, color: .clear)))
                                .zIndex(2) // Ensure preview is above everything
                        }
                        
                        // Add task preview layer
                        if isCreatingTask, let start = taskPreviewStart, let end = taskPreviewEnd {
                            TaskPreviewView(startTime: start, endTime: end)
                                .padding(.leading, 42)
                                .offset(y: calculateEventOffset(for: CalendarEvent(title: "", startTime: start, endTime: end, color: .clear)))
                                .zIndex(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if let previous = previousDragValue {
                        let delta = value.translation.width - previous.translation.width
                        dragOffset += delta
                        
                        // Just update the current view's offset
                        if selectedTag == "Event" {
                            eventOffset = dragOffset
                        } else {
                            taskOffset = dragOffset
                        }
                    }
                    previousDragValue = value
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    withAnimation(.spring()) {
                        if dragOffset > threshold {
                            selectPreviousTag()
                        } else if dragOffset < -threshold {
                            selectNextTag()
                        } else {
                            // Reset position
                            if selectedTag == "Event" {
                                eventOffset = 0
                            } else {
                                taskOffset = 0
                            }
                        }
                    }
                    dragOffset = 0
                    previousDragValue = nil
                }
        )
        .onChange(of: selectedTag) { newValue in
            withAnimation(.spring()) {
                if newValue == "Event" {
                    eventOffset = 0
                    taskOffset = UIScreen.main.bounds.width
                } else {
                    taskOffset = 0
                    eventOffset = -UIScreen.main.bounds.width
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
            if let event = authManager.selectedEvent {
                startTime = event.startTime
                endTime = event.endTime
                timelinePoints = hoursBetween(start: startTime, end: endTime)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshCalendarEvents"))) { _ in
            // Toggle forceUpdate to trigger a recalculation of filteredEvents
            forceUpdate.toggle()
        }
        .onChange(of: authManager.selectedEventId) { _ in
            if let event = authManager.selectedEvent {
                startTime = event.startTime
                endTime = event.endTime
                timelinePoints = hoursBetween(start: event.startTime, end: event.endTime)
            
            }
        }
        .sheet(isPresented: $showInviteModal) {
            InviteModalView(
                isPresented: $showInviteModal,
                selectedTag: $selectedTag,
                scrollProxy: proxy
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func selectNextTag() {
        if let currentIndex = tags.firstIndex(of: selectedTag),
           currentIndex < tags.count - 1 {
            let screenWidth = UIScreen.main.bounds.width
            let nextTag = tags[currentIndex + 1]
            withAnimation(.spring()) {
                selectedTag = nextTag
                if selectedTag == "Event" {
                    eventOffset = 0
                    taskOffset = screenWidth
                } else {
                    taskOffset = 0
                    eventOffset = -screenWidth
                }
                generateHapticFeedback()
                
                // Scroll to the newly selected tag
                withAnimation {
                    proxy?.scrollTo(nextTag, anchor: .center)
                }
            }
        }
    }

    private func selectPreviousTag() {
        if let currentIndex = tags.firstIndex(of: selectedTag),
           currentIndex > 0 {
            let screenWidth = UIScreen.main.bounds.width
            let previousTag = tags[currentIndex - 1]
            withAnimation(.spring()) {
                selectedTag = previousTag
                if selectedTag == "Event" {
                    eventOffset = 0
                    taskOffset = screenWidth
                } else {
                    taskOffset = 0
                    eventOffset = -screenWidth
                }
                generateHapticFeedback()
                
                // Scroll to the newly selected tag
                withAnimation {
                    proxy?.scrollTo(previousTag, anchor: .center)
                }
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
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date).lowercased()
    }
    
    private func formatWeekday(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        
        while currentDate <= end {
            let point = TimelinePoint(date: currentDate, yPosition: yPosition)
            points.append(point)
            currentDate = calendar.date(byAdding: .hour, value: 1, to: currentDate)!
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        let components = calendar.dateComponents([.hour, .minute], from: startTime, to: event.startTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0
    }
    
    private func createCalendarEvent(start: Date, end: Date) {
        guard let eventId = authManager.selectedEventId ?? authManager.currentUser?.events.first?.key else {
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
                    if var user = authManager.currentUser,
                       var event = user.events[eventId] {
                        // Convert the new calendar event to API format
                        let apiEvent = APICalendarEvent(
                            id: createdEvent.id,
                            title: createdEvent.title,
                            startTime: createdEvent.startTime,
                            endTime: createdEvent.endTime,
                            color: createdEvent.color
                        )
                        // Add the new event to the selected event's calendar events
                        event.calendarEvents.append(apiEvent)
                        user.events[eventId] = event
                        authManager.currentUser = user
                        
                        newEventId = calendarEvent.id
                        impactHeavy.impactOccurred()
                    }
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

    private func getTagDirection(from oldTag: String, to newTag: String) -> Edge {
        let tagOrder = tags // Use the existing tags array
        if let oldIndex = tagOrder.firstIndex(of: oldTag),
           let newIndex = tagOrder.firstIndex(of: newTag) {
            return oldIndex < newIndex ? .trailing : .leading
        }
        return .trailing
    }

    private func calculateRoundedOffset(startTime: Date) -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: startTime)
        let roundedStartTime = calendar.date(from: components) ?? startTime
        
        let hoursDifference = calendar.dateComponents([.hour], from: self.startTime, to: roundedStartTime).hour ?? 0
        return CGFloat(hoursDifference) * 72.0
    }

    private func createTask(eventId: String, startTime: Date, endTime: Date, assignee: String) {
        Task {
            do {
                let task = try await authManager.createEventTask(
                    eventId: eventId,
                    title: "New Task",
                    description: "",
                    startTime: startTime,
                    endTime: endTime,
                    initialAssignee: assignee
                )
                
                await MainActor.run {
                    if var user = authManager.currentUser {
                        if var event = user.events[eventId] {
                            event.tasks.append(task)
                            user.events[eventId] = event
                            authManager.currentUser = user
                        }
                    }
                    impactHeavy.impactOccurred()
                }
            } catch {
                print("Failed to create task:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
    }

    private func updateTaskTitle(task: EventTask) {
        Task {
            do {
                let updatedTask = try await authManager.updateEventTask(
                    taskId: task.id,
                    title: editingTaskTitle,
                    description: nil,
                    startTime: nil,
                    endTime: nil
                )
                
                await MainActor.run {
                    if var user = authManager.currentUser,
                       let eventId = authManager.selectedEventId,
                       var event = user.events[eventId],
                       let taskIndex = event.tasks.firstIndex(where: { $0.id == task.id }) {
                        event.tasks[taskIndex] = updatedTask
                        user.events[eventId] = event
                        authManager.currentUser = user
                    }
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred(intensity: 0.5)
                }
            } catch {
                print("Failed to update task title:", error)
                editingTaskTitle = task.title // Revert on failure
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.error)
            }
        }
        
        editingTaskId = nil
        isTaskTitleFocused = false
    }

    private func getTasksForTag(tag: String) -> [EventTask]? {
        if tag == "You" {
            return getFilteredTasks(forEmail: authManager.currentUser?.email)
        } else {
            return getFilteredTasks(forEmail: currentEvent?.teamMembers.first(where: { $0.name == tag })?.email)
        }
    }

    struct TaskViewModifier: ViewModifier {
        let tag: String
        let selectedTag: String
        let taskOffset: CGFloat
        let tags: [String]
        let task: EventTask
        let startTime: Date
        
        func body(content: Content) -> some View {
            content
                .frame(width: 362)
                .padding(.leading, 42)
                .padding(.trailing, 16)
                .offset(y: calculateOffset())
                .offset(x: calculateHorizontalOffset())
                .animation(.spring(), value: taskOffset)
                .zIndex(1)
        }
        
        private func calculateOffset() -> CGFloat {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: task.startTime)
            let roundedStartTime = calendar.date(from: components) ?? task.startTime
            let hoursDifference = calendar.dateComponents([.hour], from: startTime, to: roundedStartTime).hour ?? 0
            return CGFloat(hoursDifference) * 72.0
        }
        
        private func calculateHorizontalOffset() -> CGFloat {
            if selectedTag == tag {
                return taskOffset
            }
            if let selectedIndex = tags.firstIndex(of: selectedTag),
               let tagIndex = tags.firstIndex(of: tag) {
                return tagIndex < selectedIndex ? -UIScreen.main.bounds.width : UIScreen.main.bounds.width
            }
            return 0
        }
    }

    // First, add this helper function to handle task view creation
    private func createTaskView(task: EventTask, tag: String) -> some View {
        TaskTimelineView(
            task: task, 
            dayStartTime: startTime,
            isEditing: editingTaskId == task.id,
            editableTitle: Binding(
                get: { editingTaskId == task.id ? editingTaskTitle : task.title },
                set: { editingTaskTitle = $0 }
            ),
            isTitleFocused: _isTaskTitleFocused,
            onTitleTap: {
                editingTaskId = task.id
                editingTaskTitle = task.title
                isTaskTitleFocused = true
            },
            onTitleSubmit: {
                updateTaskTitle(task: task)
            }
        )
        .modifier(TaskViewModifier(
            tag: tag,
            selectedTag: selectedTag,
            taskOffset: taskOffset,
            tags: tags,
            task: task,
            startTime: startTime
        ))
        .onChange(of: isTaskTitleFocused) { focused in
            if !focused && editingTaskId == task.id {
                updateTaskTitle(task: task)
            }
        }
    }

    // Add this helper function at the top of MainContentView
    private func convertAPIEventToCalendarEvent(_ apiEvent: APICalendarEvent) -> CalendarEvent {
        let color = apiEvent.color.split(separator: ",").map { Int($0) ?? 0 }
        return CalendarEvent(
            id: UUID(uuidString: apiEvent.id) ?? UUID(),
            title: apiEvent.title,
            startTime: apiEvent.startTime,
            endTime: apiEvent.endTime,
            color: Color(
                red: CGFloat(color[0])/255.0,
                green: CGFloat(color[1])/255.0,
                blue: CGFloat(color[2])/255.0
            )
        )
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

// Add this new component
struct TaskAssigneeView: View {
    let user: AssignedUser
    let size: CGFloat = 32
    
    var body: some View {
        if let profilePicture = user.profilePicture {
            AsyncImage(url: URL(string: profilePicture)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                InitialsView(name: user.name, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            InitialsView(name: user.name, size: size)
        }
    }
}

struct InitialsView: View {
    let name: String
    let size: CGFloat
    
    private var initials: String {
        let components = name.components(separatedBy: " ")
        if let first = components.first?.prefix(1) {
            return String(first).uppercased()
        }
        return ""
    }
    
    var body: some View {
        Circle()
            .fill(Color(red: 89/255, green: 99/255, blue: 110/255))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            )
    }
}

// Update TaskTimelineView to use UTC time
struct TaskTimelineView: View {
    let task: EventTask
    let dayStartTime: Date
    let isEditing: Bool
    @Binding var editableTitle: String
    @FocusState var isTitleFocused: Bool
    let onTitleTap: () -> Void
    let onTitleSubmit: () -> Void
    @State private var showTaskDetail = false
    @EnvironmentObject var authManager: AuthManager
    
    private var roundedStartTime: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: task.startTime)
        return calendar.date(from: components) ?? task.startTime
    }
    
    private var roundedEndTime: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: task.endTime)
        // If there are any minutes, round up to the next hour
        if calendar.component(.minute, from: task.endTime) > 0 {
            components.hour = (components.hour ?? 0) + 1
        }
        return calendar.date(from: components) ?? task.endTime
    }
    
    private var duration: TimeInterval {
        roundedEndTime.timeIntervalSince(roundedStartTime)
    }
    
    private var height: CGFloat {
        let minHeight: CGFloat = 72.0 // Minimum one hour
        let calculatedHeight = CGFloat(duration / 3600.0) * 72.0 - 16
        return max(minHeight - 16, calculatedHeight)
    }
    
    private var isOneHourOrLess: Bool {
        duration <= 3600 // 1 hour or less
    }
    
    private func formatEventTime(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")  // Force UTC timezone
        
        let formatTime: (Date) -> String = { date in
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(abbreviation: "UTC")!  // Use UTC calendar
            let minutes = calendar.component(.minute, from: date)
            if minutes == 0 {
                formatter.dateFormat = "ha"  // Will show like "2pm"
            } else {
                formatter.dateFormat = "h:mm a"  // Will show like "2:30pm"
            }
            return formatter.string(from: date).lowercased()
        }
        
        let startString = formatTime(start)
        let endString = formatTime(end)
        return "\(startString) - \(endString)"
    }
    
    var body: some View {
        if isOneHourOrLess {
            HStack(spacing: 0) {
                if isEditing {
                    TextField("Task Title", text: $editableTitle)
                        .foregroundColor(.black)
                        .font(.system(size: 18))
                        .focused($isTitleFocused)
                        .onSubmit(onTitleSubmit)
                } else {
                    Text(task.title)
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(perform: onTitleTap)
                }
                
                Spacer()
                
                Text(formatEventTime(start: task.startTime, end: task.endTime))
                    .foregroundColor(.black.opacity(0.6))
                    .font(.system(size: 14))
                    .layoutPriority(1)
                
                HStack(spacing: -8) {
                    ForEach(task.assignedTo, id: \.email) { user in
                        TaskAssigneeView(user: user)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }
                .padding(.leading, 8)
            }
            .padding(16)
            .frame(height: height)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black, lineWidth: 1)
            )
            .padding(.vertical, 8)
            .onTapGesture {
                showTaskDetail = true
            }
            .sheet(isPresented: $showTaskDetail) {
                TaskDetailModalView(task: task, currentUser: $authManager.currentUser)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if isEditing {
                    TextField("Task Title", text: $editableTitle)
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .focused($isTitleFocused)
                        .onSubmit(onTitleSubmit)
                } else {
                    Text(task.title)
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .onTapGesture(perform: onTitleTap)
                }
                
                Spacer()
                
                HStack(alignment: .bottom) {
                    Text(formatEventTime(start: task.startTime, end: task.endTime))
                        .foregroundColor(.black.opacity(0.6))
                        .font(.system(size: 14))
                    
                    Spacer()
                    HStack(spacing: -8) {
                        ForEach(task.assignedTo, id: \.email) { user in
                            TaskAssigneeView(user: user)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        }
                    }
                }
            }
            .padding(16)
            .frame(height: height)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black, lineWidth: 1)
            )
            .padding(.vertical, 8)
            .onTapGesture {
                showTaskDetail = true
            }
            .sheet(isPresented: $showTaskDetail) {
                TaskDetailModalView(task: task, currentUser: $authManager.currentUser)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// Update TaskPreviewView to use UTC time
struct TaskPreviewView: View {
    let startTime: Date
    let endTime: Date
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("New Task")
                    .font(.system(size: 18))
                    .foregroundColor(.black)
                Spacer()
            }
            Spacer()
            HStack {
                Text(formatEventTime(start: startTime, end: endTime))
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.6))
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 320, height: calculateEventHeight())
        .background(Color.white.opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        )
        .padding(.vertical, 8)
        .padding(.leading, 16)
    }
    
    private func formatEventTime(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")  // Force UTC timezone
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: start).lowercased()) - \(formatter.string(from: end).lowercased())"
    }
    
    private func calculateEventHeight() -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: startTime, to: endTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0 - 16
    }
}

struct TaskDetailModalView: View {
    @State private var editableTitle: String
    @State private var editableDescription: String
    @State private var isEditingTitle: Bool = false
    @State private var isEditingDescription: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isDescriptionFocused: Bool
    
    @State private var currentStartTime: Date
    @State private var currentEndTime: Date
    @State private var isEditingStartTime: Bool = false
    @State private var isEditingEndTime: Bool = false
    
    let task: EventTask
    @Binding var currentUser: User?
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var authManager: AuthManager
    
    @State private var showDeleteConfirmation = false
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let notificationFeedback = UINotificationFeedbackGenerator()
    
    @State private var showAssigneeSheet = false
    
    init(task: EventTask, currentUser: Binding<User?>) {
        self.task = task
        self._currentUser = currentUser
        self._editableTitle = State(initialValue: task.title)
        self._editableDescription = State(initialValue: task.description)
        self._currentStartTime = State(initialValue: task.startTime)
        self._currentEndTime = State(initialValue: task.endTime)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if isEditingTitle {
                    TextField("Task Title", text: $editableTitle)
                        .font(.system(size: 24))
                        .focused($isTitleFocused)
                        .onSubmit {
                            updateTaskTitle()
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
                    // Time section
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                        
                        HStack(spacing: 4) {
                            Button(action: {
                                isEditingStartTime = true
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
                            }) {
                                Text(formatTime(date: currentEndTime))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(6)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                    
                    // Calendar section
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                        Text(formatEventDate(date: task.startTime))
                    }
                    .padding(.horizontal)
                    
                    // Description section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        
                        TextEditor(text: $editableDescription)
                            .frame(height: 200)
                            .padding(8)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(UIColor.systemGray3), lineWidth: 1)
                            )
                            .focused($isDescriptionFocused)
                            .onChange(of: isDescriptionFocused) { focused in
                                if !focused {
                                    updateTaskDescription()
                                }
                            }
                    }
                    .padding(.horizontal)
                    
                    // Assignees section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Assigned to")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                showAssigneeSheet = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(red: 89/255, green: 99/255, blue: 110/255))
                                    .font(.system(size: 24))
                            }
                        }
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            ForEach(task.assignedTo, id: \.email) { user in
                                HStack(spacing: 12) {
                                    if let profilePicture = user.profilePicture {
                                        AsyncImage(url: URL(string: profilePicture)) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                        } placeholder: {
                                            InitialsView(name: user.name, size: 40)
                                        }
                                    } else {
                                        InitialsView(name: user.name, size: 40)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.name)
                                            .font(.system(size: 16, weight: .medium))
                                        Text(user.email)
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    if task.assignedTo.count > 1 {
                                        Button(action: {
                                            unassignUser(email: user.email)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(Color(UIColor.systemGray3))
                                                .font(.system(size: 20))
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .sheet(isPresented: $showAssigneeSheet) {
                            AssigneeSelectionView(
                                currentAssignees: task.assignedTo,
                                teamMembers: currentUser?.events.first?.value.teamMembers ?? [],
                                onAssign: { email in
                                    assignUser(email: email)
                                    showAssigneeSheet = false
                                }
                            )
                            .presentationDetents([.medium])
                            .presentationDragIndicator(.visible)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: $isEditingStartTime) {
            TimePickerView(
                selectedDate: $currentStartTime,
                isPresented: $isEditingStartTime
            )
            .presentationDetents([.height(300)])
            .onDisappear {
                updateTaskTimes()
            }
        }
        .sheet(isPresented: $isEditingEndTime) {
            TimePickerView(
                selectedDate: $currentEndTime,
                isPresented: $isEditingEndTime
            )
            .presentationDetents([.height(300)])
            .onDisappear {
                updateTaskTimes()
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Task"),
                message: Text("Are you sure you want to delete this task?"),
                primaryButton: .destructive(Text("Delete")) {
                    deleteTask()
                },
                secondaryButton: .cancel()
            )
        }
        .onChange(of: isTitleFocused) { focused in
            if !focused {
                updateTaskTitle()
            }
        }
        .onChange(of: isDescriptionFocused) { focused in
            if !focused {
                updateTaskDescription()
            }
        }
    }
    
    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(abbreviation: "UTC")  // Force UTC timezone
        return formatter.string(from: date).lowercased()
    }
    
    private func updateTaskTitle() {
        Task {
            do {
                let updatedTask = try await authManager.updateEventTask(
                    taskId: task.id,
                    title: editableTitle,
                    description: nil,
                    startTime: nil,
                    endTime: nil
                )
                
                await MainActor.run {
                    if var user = authManager.currentUser,
                       let eventId = authManager.selectedEventId,
                       var event = user.events[eventId],
                       let taskIndex = event.tasks.firstIndex(where: { $0.id == task.id }) {
                        event.tasks[taskIndex] = updatedTask
                        user.events[eventId] = event
                        authManager.currentUser = user
                    }
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred(intensity: 0.5)
                }
            } catch {
                print("Failed to update task title:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
        isEditingTitle = false
        isTitleFocused = false
    }
    
    private func updateTaskDescription() {
        Task {
            do {
                let updatedTask = try await authManager.updateEventTask(
                    taskId: task.id,
                    title: nil,
                    description: editableDescription,
                    startTime: nil,
                    endTime: nil
                )
                
                await MainActor.run {
                    if var user = authManager.currentUser,
                       let eventId = authManager.selectedEventId,
                       var event = user.events[eventId],
                       let taskIndex = event.tasks.firstIndex(where: { $0.id == task.id }) {
                        event.tasks[taskIndex] = updatedTask
                        user.events[eventId] = event
                        authManager.currentUser = user
                    }
                    impactMed.impactOccurred(intensity: 0.5)
                }
            } catch {
                print("Failed to update task description:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
        isEditingDescription = false
        isDescriptionFocused = false
    }
    
    private func updateTaskTimes() {
        if currentEndTime <= currentStartTime {
            notificationFeedback.notificationOccurred(.error)
            currentStartTime = task.startTime
            currentEndTime = task.endTime
            return
        }
        
        Task {
            do {
                let updatedTask = try await authManager.updateEventTask(
                    taskId: task.id,
                    title: nil,
                    description: nil,
                    startTime: currentStartTime,
                    endTime: currentEndTime
                )
                
                await MainActor.run {
                    updateLocalTask(updatedTask)
                    impactMed.impactOccurred(intensity: 0.5)
                }
            } catch {
                print("Failed to update task times:", error)
                currentStartTime = task.startTime
                currentEndTime = task.endTime
                notificationFeedback.notificationOccurred(.error)
            }
        }
    }
    
    private func deleteTask() {
        Task {
            do {
                try await authManager.deleteEventTask(taskId: task.id)
                await MainActor.run {
                    if var user = currentUser,
                       let eventId = user.events.first?.key,
                       var event = user.events[eventId] {
                        event.tasks.removeAll { $0.id == task.id }
                        user.events[eventId] = event
                        currentUser = user
                        impactMed.impactOccurred()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                print("Failed to delete task:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
    }
    
    private func updateLocalTask(_ updatedTask: EventTask) {
        if var user = currentUser,
           let eventId = user.events.first?.key,
           var event = user.events[eventId],
           let taskIndex = event.tasks.firstIndex(where: { $0.id == task.id }) {
            event.tasks[taskIndex] = updatedTask
            user.events[eventId] = event
            currentUser = user
        }
    }

    // Update TaskDetailModalView to use UTC time
    private func formatEventDate(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        formatter.timeZone = TimeZone(abbreviation: "UTC")  // Force UTC timezone
        return formatter.string(from: date)
    }

    private func assignUser(email: String) {
        Task {
            do {
                let updatedTask = try await authManager.assignEventTask(
                    taskId: task.id,
                    assigneeEmail: email
                )
                
                await MainActor.run {
                    updateLocalTask(updatedTask)
                    impactMed.impactOccurred()
                }
            } catch {
                print("Failed to assign user:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
    }

    private func unassignUser(email: String) {
        Task {
            do {
                let updatedTask = try await authManager.unassignEventTask(
                    taskId: task.id,
                    userEmailToRemove: email
                )
                
                await MainActor.run {
                    updateLocalTask(updatedTask)
                    impactMed.impactOccurred()
                }
            } catch {
                print("Failed to unassign user:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
    }
}

struct AssigneeSelectionView: View {
    let currentAssignees: [AssignedUser]
    let teamMembers: [TeamMember]
    let onAssign: (String) -> Void
    @EnvironmentObject var authManager: AuthManager
    
    var availableMembers: [TeamMember] {
        teamMembers.filter { member in
            !currentAssignees.contains { $0.email == member.email }
        }
    }
    
    var currentUserAvailable: Bool {
        guard let currentUserEmail = authManager.currentUser?.email else { return false }
        return !currentAssignees.contains { $0.email == currentUserEmail }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Combined section with current user first
                if currentUserAvailable, let currentUser = authManager.currentUser {
                    Button(action: {
                        onAssign(currentUser.email)
                    }) {
                        HStack(spacing: 12) {
                            if let profilePicture = currentUser.profilePictureUrl {
                                AsyncImage(url: URL(string: profilePicture)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } placeholder: {
                                    InitialsView(name: currentUser.name, size: 40)
                                }
                            } else {
                                InitialsView(name: currentUser.name, size: 40)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You")
                                    .font(.system(size: 16, weight: .medium))
                                Text(currentUser.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                ForEach(availableMembers, id: \.email) { member in
                    Button(action: {
                        onAssign(member.email)
                    }) {
                        HStack(spacing: 12) {
                            if let profilePicture = member.profilePicture {
                                AsyncImage(url: URL(string: profilePicture)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } placeholder: {
                                    InitialsView(name: member.name, size: 40)
                                }
                            } else {
                                InitialsView(name: member.name, size: 40)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .font(.system(size: 16, weight: .medium))
                                Text(member.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Team Member")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

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
            .environment(\.timeZone, TimeZone(abbreviation: "UTC")!)  // Force UTC timezone
            .navigationBarItems(
                trailing: Button("Done") {
                    isPresented = false
                }
            )
            .padding()
        }
    }
}

struct InviteModalView: View {
    @Binding var isPresented: Bool
    @Binding var selectedTag: String
    let scrollProxy: ScrollViewProxy?
    
    @State private var email: String = ""
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @EnvironmentObject var authManager: AuthManager
    
    @State private var isCheckingEmail = false
    @State private var emailCheckTimer: Timer?
    @State private var isExistingUser = false
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Team Member Details")) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .onChange(of: email) { newValue in
                            emailCheckTimer?.invalidate()
                            if newValue.contains("@") && newValue.contains(".") {
                                emailCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                    checkEmail()
                                }
                            }
                        }
                    
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .disabled(isCheckingEmail)
                        .overlay(
                            Group {
                                if isCheckingEmail {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    }
                                }
                            }
                        )
                }
                
                Section(header: Text("Role Description (Optional)")) {
                    TextEditor(text: $role)
                        .frame(height: 100)
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Invite Team Member")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    isPresented = false
                }
            )
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Button(action: inviteUser) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(.white)
                        } else {
                            Text("Send Invite")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        email.isEmpty || name.isEmpty || isLoading || isCheckingEmail ?
                            Color.blue.opacity(0.5) :
                            Color.blue
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .disabled(email.isEmpty || name.isEmpty || isLoading || isCheckingEmail)
                }
                .padding(.bottom)
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .onDisappear {
            emailCheckTimer?.invalidate()
        }
    }
    
    private func checkEmail() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }
        
        isCheckingEmail = true
        
        Task {
            do {
                let result = try await authManager.checkUserExists(email: trimmedEmail)
                await MainActor.run {
                    isExistingUser = result.exists
                    if let existingName = result.name {
                        name = existingName
                        impactMed.impactOccurred(intensity: 0.5)
                    }
                    isCheckingEmail = false
                }
            } catch {
                await MainActor.run {
                    isCheckingEmail = false
                }
            }
        }
    }
    
    private func inviteUser() {
        guard let eventId = authManager.selectedEventId else {
            error = "No event selected"
            return
        }
        
        isLoading = true
        error = nil
        
        Task {
            do {
                print("\n=== Sending Invite ===")
                let newTeamMember = try await authManager.inviteUserToEvent(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    roleDescription: role.isEmpty ? nil : role.trimmingCharacters(in: .whitespacesAndNewlines),
                    eventId: eventId
                )
                
                await MainActor.run {
                    print("\nInvite successful:")
                    print("New team member:", newTeamMember.name)
                    
                    // Switch to the new team member's tab
                    withAnimation {
                        selectedTag = newTeamMember.name
                        if let proxy = scrollProxy {
                            proxy.scrollTo(newTeamMember.name, anchor: .center)
                        }
                    }
                    
                    impactMed.impactOccurred()
                    isPresented = false
                }
            } catch AuthError.notAuthorized {
                error = "You don't have permission to invite users to this event"
                notificationFeedback.notificationOccurred(.error)
            } catch AuthError.userAlreadyInvited(let message) {
                error = message
                notificationFeedback.notificationOccurred(.error)
            } catch {
                print("\nInvite error:", error)
                self.error = "Failed to send invite. Please try again."
                notificationFeedback.notificationOccurred(.error)
            }
            
            isLoading = false
        }
    }
}
