import SwiftUI
import UIKit

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

struct ContentView: View {
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

                AsyncImageView(url: URL(string: "https://thispersondoesnotexist.com")!)
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
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    // Add this state variable for the delete confirmation alert
    @State private var showDeleteConfirmation = false
    
    @State private var editableTitle: String
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFocused: Bool
    
    init(event: CalendarEvent, events: Binding<[CalendarEvent]>) {
        self.event = event
        self._events = events
        self._selectedColor = State(initialValue: event.color)
        self._editableTitle = State(initialValue: event.title)
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
                        Text(formatEventTime(start: event.startTime, end: event.endTime))
                        Spacer()
                    }
                    .padding(.horizontal)
                    
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
            impactHeavy.impactOccurred()
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
}

#Preview {
    ContentView()
}
