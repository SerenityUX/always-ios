//
//  ContentView.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
     
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if let firstEvent = authManager.currentUser?.events.first?.value {
                    MainContentView(initialEvents: firstEvent.calendar_events.map { calendarEvent in
                        let color = rgbStringToColor(calendarEvent.color)
                        return CalendarEvent(
                            id: UUID(uuidString: calendarEvent.id)!,
                            title: calendarEvent.title,
                            startTime: calendarEvent.startTime,
                            endTime: calendarEvent.endTime,
                            color: color
                        )
                    })
                } else {
                    MainContentView()
                }
            } else {
                OnboardingView()
            }
        }
        .environmentObject(authManager)
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

#Preview {
    ContentView()
        .preferredColorScheme(.light)
}
