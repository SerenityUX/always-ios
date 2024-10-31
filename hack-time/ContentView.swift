//
//  ContentView.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @State private var initialEvents: [CalendarEvent] = []
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if let event = authManager.selectedEvent {
                    // Convert APICalendarEvents to CalendarEvents
                    let calendarEvents = event.calendarEvents.map { apiEvent in
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
                    MainContentView(initialEvents: calendarEvents)
                        .environmentObject(authManager)
                } else {
                    MainContentView()
                        .environmentObject(authManager)
                }
            } else {
                OnboardingView()
                    .environmentObject(authManager)
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
