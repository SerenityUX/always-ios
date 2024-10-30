//
//  EventViews.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct EventView: View {
    let event: CalendarEvent
    let dayStartTime: Date
    @State private var isEditing: Bool = false
    @Binding var events: [CalendarEvent]
    @FocusState private var isFocused: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @EnvironmentObject var authManager: AuthManager

    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let notificationFeedback = UINotificationFeedbackGenerator()

    private var editableTitle: String {
        get { event.title }
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
    
    private func calculateEventHeight() -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: event.startTime, to: event.endTime)
        let hours = CGFloat(components.hour ?? 0)
        let minutes = CGFloat(components.minute ?? 0)
        return (hours + minutes / 60) * 72.0 - 16
    }

    private func updateEventTitle() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            if events[index].title.isEmpty {
                Task {
                    do {
                        try await authManager.deleteCalendarEvent(calendarEventId: event.id.uuidString)
                        await MainActor.run {
                            events.remove(at: index)
                            let impact = UIImpactFeedbackGenerator(style: .heavy)
                            impact.impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                impact.impactOccurred()
                            }
                        }
                    } catch {
                        print("Failed to delete event:", error)
                    }
                }
            } else {
                Task {
                    do {
                        _ = try await authManager.updateCalendarEvent(
                            calendarEventId: event.id.uuidString,
                            title: events[index].title,
                            startTime: nil as Date?,
                            endTime: nil as Date?,
                            color: nil as String?
                        )
                    } catch {
                        print("Failed to update event title:", error)
                    }
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
            let newStartTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: event.startTime)!
            let newEndTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: event.endTime)!
            
            Task {
                do {
                    _ = try await authManager.updateCalendarEvent(
                        calendarEventId: event.id.uuidString,
                        title: nil as String?,
                        startTime: newStartTime,
                        endTime: newEndTime,
                        color: nil as String?
                    )
                    await MainActor.run {
                        events[index].startTime = newStartTime
                        events[index].endTime = newEndTime
                    }
                } catch {
                    print("Failed to update event times:", error)
                }
            }
        }
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

struct EventDetailModalView: View {
    @State private var selectedColor: Color
    var event: CalendarEvent
    @Binding var events: [CalendarEvent]
    @Environment(\.presentationMode) var presentationMode
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let notificationFeedback = UINotificationFeedbackGenerator()
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
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
    
    @EnvironmentObject var authManager: AuthManager

    init(event: CalendarEvent, events: Binding<[CalendarEvent]>) {
        self.event = event
        self._events = events
        self._selectedColor = State(initialValue: event.color)
        self._editableTitle = State(initialValue: event.title)
        self._currentStartTime = State(initialValue: event.startTime)
        self._currentEndTime = State(initialValue: event.endTime)
    }
    
    let colorOptions: [Color] = [
        Color(red: 218/255, green: 128/255, blue: 0/255),
        Color(red: 2/255, green: 147/255, blue: 212/255),
        Color(red: 8/255, green: 164/255, blue: 42/255),
        Color(red: 142/255, green: 8/255, blue: 164/255),
        Color(red: 190/255, green: 58/255, blue: 44/255),
        Color(red: 89/255, green: 89/255, blue: 89/255)
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
                                        impactMed.impactOccurred()
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
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
    
    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatEventDate(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func deleteEvent() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            Task {
                do {
                    try await authManager.deleteCalendarEvent(calendarEventId: event.id.uuidString)
                    await MainActor.run {
                        events.remove(at: index)
                        impactMed.impactOccurred()
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    print("Failed to delete event:", error)
                    notificationFeedback.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func updateEventTitle() {
        let newTitle = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            Task {
                do {
                    let updatedEvent = try await authManager.updateCalendarEvent(
                        calendarEventId: event.id.uuidString,
                        title: newTitle,
                        startTime: nil,
                        endTime: nil,
                        color: nil
                    )
                    
                    if let updatedTitle = updatedEvent.title {
                        await MainActor.run {
                            events[index].title = updatedTitle
                            impactMed.impactOccurred(intensity: 0.5)
                        }
                    }
                } catch {
                    print("Failed to update event title:", error)
                    notificationFeedback.notificationOccurred(.error)
                }
            }
            isEditingTitle = false
            isTitleFocused = false
        }
    }
    
    private func updateEventColor() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            let colorString = colorToRGBString(selectedColor)
            
            Task {
                do {
                    let updatedEvent = try await authManager.updateCalendarEvent(
                        calendarEventId: event.id.uuidString,
                        title: nil,
                        startTime: nil,
                        endTime: nil,
                        color: colorString
                    )
                    
                    if let updatedColor = updatedEvent.color {
                        await MainActor.run {
                            let color = rgbStringToColor(updatedColor)
                            events[index].color = color
                            impactMed.impactOccurred()
                        }
                    }
                } catch {
                    print("Failed to update event color:", error)
                    notificationFeedback.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func updateEventTimes() {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            if currentEndTime <= currentStartTime {
                notificationFeedback.notificationOccurred(.error)
                currentStartTime = events[index].startTime
                currentEndTime = events[index].endTime
                return
            }
            
            let wouldOverlap = events.contains { otherEvent in
                guard otherEvent.id != event.id else { return false }
                return (currentStartTime < otherEvent.endTime && 
                        currentEndTime > otherEvent.startTime)
            }
            
            if wouldOverlap {
                notificationFeedback.notificationOccurred(.error)
                currentStartTime = events[index].startTime
                currentEndTime = events[index].endTime
                return
            }
            
            Task {
                do {
                    let updatedEvent = try await authManager.updateCalendarEvent(
                        calendarEventId: event.id.uuidString,
                        title: nil,
                        startTime: currentStartTime,
                        endTime: currentEndTime,
                        color: nil
                    )
                    
                    if let newStartTime = updatedEvent.startTime,
                       let newEndTime = updatedEvent.endTime {
                        await MainActor.run {
                            events[index].startTime = newStartTime
                            events[index].endTime = newEndTime
                            impactMed.impactOccurred(intensity: 0.5)
                        }
                    }
                } catch {
                    print("Failed to update event times:", error)
                    await MainActor.run {
                        currentStartTime = events[index].startTime
                        currentEndTime = events[index].endTime
                        notificationFeedback.notificationOccurred(.error)
                    }
                }
            }
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
            .navigationBarItems(
                trailing: Button("Done") {
                    isPresented = false
                }
            )
            .padding()
        }
    }
}
