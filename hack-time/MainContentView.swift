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
            
            ScrollViewReader { scrollProxy in
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
                                    withAnimation {
                                        selectedTag = tag
                                        scrollProxy.scrollTo(tag, anchor: .center)
                                    }
                                    generateHapticFeedback()
                                }
                                .id(tag)
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
                                           let eventId = authManager.currentUser?.events.first?.key {
                                            
                                            let assigneeEmail = selectedTag == "You" ?
                                                authManager.currentUser?.email :
                                                currentEvent?.teamMembers.first { $0.name == selectedTag }?.email
                                            
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
        let newTitle = editingTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                let updatedTask = try await authManager.updateEventTask(
                    taskId: task.id,
                    title: newTitle
                )
                
                await MainActor.run {
                    if var user = authManager.currentUser,
                       let eventId = user.events.first?.key,
                       var event = user.events[eventId],
                       let taskIndex = event.tasks.firstIndex(where: { $0.id == task.id }) {
                        event.tasks[taskIndex].title = newTitle
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

// Update TaskTimelineView
struct TaskTimelineView: View {
    let task: EventTask
    let dayStartTime: Date
    let isEditing: Bool
    @Binding var editableTitle: String
    @FocusState var isTitleFocused: Bool
    let onTitleTap: () -> Void
    let onTitleSubmit: () -> Void
    
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
        
        let formatTime: (Date) -> String = { date in
            let calendar = Calendar.current
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
        }
    }
}

// Add this view for task preview
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
