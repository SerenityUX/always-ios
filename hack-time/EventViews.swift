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
    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    let notificationFeedback = UINotificationFeedbackGenerator()

    @State private var currentTitle: String

    init(event: CalendarEvent, dayStartTime: Date, events: Binding<[CalendarEvent]>, isNewEvent: Bool = false) {
        self.event = event
        self.dayStartTime = dayStartTime
        self._events = events
        self._isEditing = State(initialValue: isNewEvent)
        self._currentTitle = State(initialValue: event.title)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("New Event", text: isEditing ? $currentTitle : .constant(event.title))
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
                currentTitle = event.title
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
        // .gesture(
        //     DragGesture()
        //         .onChanged { value in
        //             isDragging = true
        //             let proposedOffset = value.translation.height
        //             let snappedOffset = snapToNearestHour(offset: proposedOffset)
                    
        //             if !wouldOverlap(with: snappedOffset) {
        //                 dragOffset = snappedOffset
        //                 impactMed.impactOccurred(intensity: 0.5)
        //             } else {
        //                 notificationFeedback.notificationOccurred(.error)
        //             }
        //         }
        //         .onEnded { _ in
        //             isDragging = false
        //             updateEventTime()
        //             dragOffset = 0
        //         }
        // )
        .animation(.interactiveSpring(), value: dragOffset)
        .onAppear {
            if isEditing {
                isFocused = true
            }
        }
    }
    
    private func formatEventTime(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let formatTime: (Date) -> String = { date in
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(abbreviation: "UTC")!
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
        print("\n=== Event Title Update ===")
        let newTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Updating event title to:", newTitle)
        print("Event ID:", event.id.uuidString)
        print("Selected Event ID:", authManager.selectedEventId ?? "nil")
        
        Task {
            do {
                print("\nSending API request to update title")
                let updatedEvent = try await authManager.updateCalendarEvent(
                    calendarEventId: event.id.uuidString,
                    title: newTitle,
                    startTime: nil,
                    endTime: nil,
                    color: nil
                )
                
                await MainActor.run {
                    print("\nAPI Response successful, updating state")
                    // Update local events array
                    if let index = events.firstIndex(where: { $0.id == event.id }) {
                        print("\nUpdating local events array at index:", index)
                        events[index].title = newTitle
                    } else {
                        print("Error: Could not find event in local events array")
                    }
                    
                    // Update AuthManager state
                    if let eventId = authManager.selectedEventId {
                        print("\nUpdating AuthManager state for event:", eventId)
                        authManager.updateCalendarEventInState(
                            eventId: eventId,
                            calendarEventId: event.id.uuidString
                        ) { calendarEvent in
                            print("Previous title:", calendarEvent.title)
                            calendarEvent.title = newTitle
                            print("New title:", calendarEvent.title)
                        }
                        
                        // Force a UI refresh of the calendar view
                        authManager.objectWillChange.send()
                    } else {
                        print("Error: No selected event ID in AuthManager")
                    }
                    
                    print("\nFinal state check:")
                    print("Selected event calendar events:", 
                          authManager.selectedEvent?.calendarEvents
                            .map { "ID: \($0.id), Title: \($0.title)" }
                            .joined(separator: "\n  ") ?? "nil")
                    
                    impactMed.impactOccurred(intensity: 0.5)
                }
            } catch {
                print("\nError updating event title:", error)
                notificationFeedback.notificationOccurred(.error)
                currentTitle = event.title
                if let index = events.firstIndex(where: { $0.id == event.id }) {
                    events[index].title = event.title
                }
            }
        }
        isEditing = false
        isFocused = false
        print("=======================\n")
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

    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        return formatter.string(from: date).lowercased()
    }

    private func updateEventTime() {
        print("\n=== Event Time Update (Drag) ===")
        print("Event ID:", event.id.uuidString)
        print("Selected Event ID:", authManager.selectedEventId ?? "nil")
        
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            let minutesToAdd = Int(dragOffset / 72.0 * 60)
            let newStartTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: event.startTime)!
            let newEndTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: event.endTime)!
            
            print("Current drag offset:", dragOffset)
            print("Minutes to add:", minutesToAdd)
            print("New start time:", formatTime(date: newStartTime))
            print("New end time:", formatTime(date: newEndTime))
            
            Task {
                do {
                    print("\nSending API request to update times")
                    let updatedEvent = try await authManager.updateCalendarEvent(
                        calendarEventId: event.id.uuidString,
                        title: nil,
                        startTime: newStartTime,
                        endTime: newEndTime,
                        color: nil
                    )
                    
                    await MainActor.run {
                        print("\nAPI Response successful, updating state")
                        // Update local events array with response data
                        if let index = events.firstIndex(where: { $0.id == event.id }) {
                            print("\nUpdating local events array at index:", index)
                            events[index].startTime = updatedEvent.startTime ?? events[index].startTime
                            events[index].endTime = updatedEvent.endTime ?? events[index].endTime
                        }
                        
                        // Update AuthManager state with response data
                        if let eventId = authManager.selectedEventId {
                            print("\nUpdating AuthManager state for event:", eventId)
                            authManager.updateCalendarEventInState(
                                eventId: eventId,
                                calendarEventId: event.id.uuidString
                            ) { calendarEvent in
                                print("Previous times - Start:", formatTime(date: calendarEvent.startTime))
                                print("Previous times - End:", formatTime(date: calendarEvent.endTime))
                                // Use the response data to update the state
                                if let newStartTime = updatedEvent.startTime {
                                    calendarEvent.startTime = newStartTime
                                }
                                if let newEndTime = updatedEvent.endTime {
                                    calendarEvent.endTime = newEndTime
                                }
                                print("New times - Start:", formatTime(date: calendarEvent.startTime))
                                print("New times - End:", formatTime(date: calendarEvent.endTime))
                            }
                            
                            // Force UI updates
                            authManager.objectWillChange.send()
                            NotificationCenter.default.post(
                                name: NSNotification.Name("RefreshCalendarEvents"),
                                object: nil,
                                userInfo: [
                                    "eventId": eventId,
                                    "calendarEventId": event.id.uuidString,
                                    "startTime": updatedEvent.startTime as Any,
                                    "endTime": updatedEvent.endTime as Any
                                ]
                            )
                        }
                        
                        impactMed.impactOccurred(intensity: 0.5)
                    }
                } catch {
                    print("\nError updating event times:", error)
                    notificationFeedback.notificationOccurred(.error)
                    // Revert times on error
                    events[index].startTime = event.startTime
                    events[index].endTime = event.endTime
                }
            }
        }
        print("=======================\n")
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
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        
        let formatTime: (Date) -> String = { date in
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(abbreviation: "UTC")!
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
            
            // Add this new button section at the bottom
            if event.title.isEmpty {  // Only show for new events
                Button(action: {
                    updateEventTitle()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Create")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color.blue)
                .cornerRadius(10)
                .padding()
            }
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
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        return formatter.string(from: date).lowercased()
    }
    
    private func formatEventDate(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func deleteEvent() {
        print("\n=== Deleting Calendar Event ===")
        print("Event ID to delete:", event.id.uuidString)
        print("Selected Event ID:", authManager.selectedEventId ?? "nil")
        
        Task {
            do {
                print("\nSending delete request to API")
                try await authManager.deleteCalendarEvent(calendarEventId: event.id.uuidString)
                
                await MainActor.run {
                    print("\nAPI delete successful, updating state")
                    
                    // Remove from local events array
                    if let index = events.firstIndex(where: { $0.id == event.id }) {
                        print("Removing event from local events array at index:", index)
                        events.remove(at: index)
                    } else {
                        print("Warning: Event not found in local events array")
                    }
                    
                    // Update AuthManager state
                    if var user = authManager.currentUser,
                       let eventId = authManager.selectedEventId,
                       var selectedEvent = user.events[eventId] {
                        print("\nUpdating AuthManager state")
                        print("Before removal - Calendar events count:", selectedEvent.calendarEvents.count)
                        
                        // Remove the calendar event
                        selectedEvent.calendarEvents.removeAll { 
                            print("Comparing: \($0.id) with \(event.id.uuidString)")
                            return $0.id.lowercased() == event.id.uuidString.lowercased() 
                        }
                        
                        print("After removal - Calendar events count:", selectedEvent.calendarEvents.count)
                        
                        // Update the event in the user's dictionary
                        user.events[eventId] = selectedEvent
                        
                        // Force a complete state refresh
                        authManager.currentUser = nil  // Force a clean state
                        authManager.currentUser = user // Reassign to trigger update
                        
                        // Notify views to refresh
                        authManager.objectWillChange.send()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("RefreshCalendarEvents"),
                            object: nil
                        )
                    } else {
                        print("Error: Could not update AuthManager state")
                        print("Current user exists:", authManager.currentUser != nil)
                        print("Selected event ID exists:", authManager.selectedEventId != nil)
                    }
                    
                    impactMed.impactOccurred()
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                print("\nError deleting event:", error)
                notificationFeedback.notificationOccurred(.error)
            }
        }
        print("===========================\n")
    }
    
    private func updateEventTitle() {
        print("\n=== Event Title Update (Modal) ===")
        let newTitle = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Updating event title to:", newTitle)
        print("Event ID:", event.id.uuidString)
        print("Selected Event ID:", authManager.selectedEventId ?? "nil")
        
        Task {
            do {
                print("\nSending API request to update title")
                let updatedEvent = try await authManager.updateCalendarEvent(
                    calendarEventId: event.id.uuidString,
                    title: newTitle,
                    startTime: nil,
                    endTime: nil,
                    color: nil
                )
                
                await MainActor.run {
                    print("\nAPI Response successful, updating state")
                    // Update local events array
                    if let index = events.firstIndex(where: { $0.id == event.id }) {
                        print("\nUpdating local events array at index:", index)
                        events[index].title = newTitle
                    } else {
                        print("Error: Could not find event in local events array")
                    }
                    
                    // Update AuthManager state
                    if let eventId = authManager.selectedEventId {
                        print("\nUpdating AuthManager state for event:", eventId)
                        authManager.updateCalendarEventInState(
                            eventId: eventId,
                            calendarEventId: event.id.uuidString
                        ) { calendarEvent in
                            print("Previous title:", calendarEvent.title)
                            calendarEvent.title = newTitle
                            print("New title:", calendarEvent.title)
                        }
                        
                        // Force a UI refresh of the calendar view
                        authManager.objectWillChange.send()
                    } else {
                        print("Error: No selected event ID in AuthManager")
                    }
                    
                    print("\nFinal state check:")
                    print("Selected event calendar events:", 
                          authManager.selectedEvent?.calendarEvents
                            .map { "ID: \($0.id), Title: \($0.title)" }
                            .joined(separator: "\n  ") ?? "nil")
                    
                    impactMed.impactOccurred(intensity: 0.5)
                }
            } catch {
                print("\nError updating event title:", error)
                notificationFeedback.notificationOccurred(.error)
                editableTitle = event.title
            }
        }
        isEditingTitle = false
        isTitleFocused = false
        print("=======================\n")
    }
    
    private func updateEventColor() {
        let colorString = colorToRGBString(selectedColor)
        print("\n=== Event Color Update ===")
        print("Updating event color to:", colorString)
        print("Event ID:", event.id.uuidString)
        print("Selected Event ID:", authManager.selectedEventId ?? "nil")
        
        Task {
            do {
                let updatedEvent = try await authManager.updateCalendarEvent(
                    calendarEventId: event.id.uuidString,
                    title: nil,
                    startTime: nil,
                    endTime: nil,
                    color: colorString
                )
                
                print("\nAPI Response:")
                print("Updated color:", updatedEvent.color ?? "nil")
                
                await MainActor.run {
                    // Update local events array
                    if let index = events.firstIndex(where: { $0.id == event.id }) {
                        print("\nUpdating local events array at index:", index)
                        events[index].color = selectedColor
                    } else {
                        print("Error: Could not find event in local events array")
                    }
                    
                    // Update the state in AuthManager
                    if let eventId = authManager.selectedEventId {
                        print("\nUpdating AuthManager state for event:", eventId)
                        authManager.updateCalendarEventInState(
                            eventId: eventId,
                            calendarEventId: event.id.uuidString
                        ) { calendarEvent in
                            print("Previous color:", calendarEvent.color)
                            calendarEvent.color = colorString
                            print("New color:", calendarEvent.color)
                        }
                        
                        // Force a UI refresh of the calendar view
                        authManager.objectWillChange.send()
                    } else {
                        print("Error: No selected event ID in AuthManager")
                    }
                    
                    print("\nFinal state check:")
                    print("Selected event calendar events:", 
                          authManager.selectedEvent?.calendarEvents
                            .map { "ID: \($0.id), Color: \($0.color)" }
                            .joined(separator: "\n  ") ?? "nil")
                    
                    impactMed.impactOccurred()
                }
            } catch {
                print("\nError updating event color:", error)
                notificationFeedback.notificationOccurred(.error)
                selectedColor = event.color
            }
        }
        print("=======================\n")
    }
    
    private func colorToRGBString(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return "\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255))"
    }
    
    private func rgbStringToColor(_ rgb: String) -> Color {
        let components = rgb.split(separator: ",").map { Int($0) ?? 0 }
        guard components.count >= 3 else { return .gray }
        
        return Color(
            red: CGFloat(components[0]) / 255.0,
            green: CGFloat(components[1]) / 255.0,
            blue: CGFloat(components[2]) / 255.0
        )
    }
    
    private func updateEventTimes() {
        print("\n=== Event Time Update ===")
        print("Updating event times:")
        print("Event ID:", event.id.uuidString)
        print("Selected Event ID:", authManager.selectedEventId ?? "nil")
        print("Current Start Time:", formatTime(date: currentStartTime))
        print("Current End Time:", formatTime(date: currentEndTime))
        
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            if currentEndTime <= currentStartTime {
                print("Error: End time must be after start time")
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
                print("Error: Time range would overlap with another event")
                notificationFeedback.notificationOccurred(.error)
                currentStartTime = events[index].startTime
                currentEndTime = events[index].endTime
                return
            }
            
            Task {
                do {
                    print("\nSending API request to update times")
                    let updatedEvent = try await authManager.updateCalendarEvent(
                        calendarEventId: event.id.uuidString,
                        title: nil,
                        startTime: currentStartTime,
                        endTime: currentEndTime,
                        color: nil
                    )
                    
                    await MainActor.run {
                        print("\nAPI Response successful, updating state")
                        // Update local events array
                        events[index].startTime = currentStartTime
                        events[index].endTime = currentEndTime
                        
                        // Update AuthManager state
                        if let eventId = authManager.selectedEventId {
                            print("\nUpdating AuthManager state for event:", eventId)
                            authManager.updateCalendarEventInState(
                                eventId: eventId,
                                calendarEventId: event.id.uuidString
                            ) { calendarEvent in
                                print("Previous times - Start:", formatTime(date: calendarEvent.startTime), "End:", formatTime(date: calendarEvent.endTime))
                                calendarEvent.startTime = currentStartTime
                                calendarEvent.endTime = currentEndTime
                                print("New times - Start:", formatTime(date: calendarEvent.startTime), "End:", formatTime(date: calendarEvent.endTime))
                            }
                            
                            // Force a UI refresh of the calendar view
                            authManager.objectWillChange.send()
                        }
                        
                        print("\nFinal state check:")
                        if let selectedEvent = authManager.selectedEvent {
                            print("Selected event calendar events:")
                            for calEvent in selectedEvent.calendarEvents {
                                print("ID: \(calEvent.id)")
                                print("  Start: \(formatTime(date: calEvent.startTime))")
                                print("  End: \(formatTime(date: calEvent.endTime))")
                            }
                        }
                        
                        impactMed.impactOccurred(intensity: 0.5)
                    }
                } catch {
                    print("\nError updating event times:", error)
                    notificationFeedback.notificationOccurred(.error)
                    currentStartTime = events[index].startTime
                    currentEndTime = events[index].endTime
                }
            }
        }
        print("=======================\n")
    }
}
