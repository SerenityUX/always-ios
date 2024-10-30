//
//  AuthManager.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI
import Foundation

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String?
    @Published var isLoading = false
    @Published var currentUser: User?
    @Published var selectedEventId: String? {
        didSet {
            if let eventId = selectedEventId {
                UserDefaults.standard.set(eventId, forKey: "selectedEventId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedEventId")
            }
        }
    }

    private let baseURL = "https://serenidad.click/hacktime"

    init() {
        // Check for saved auth token
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            isAuthenticated = true  // Set this to true if we have a token
            // Load the saved event ID
            selectedEventId = UserDefaults.standard.string(forKey: "selectedEventId")
            
            // Validate token and load user data
            Task {
                do {
                    let userData = try await validateToken(token)
                    await MainActor.run {
                        self.currentUser = userData
                        // If no event is selected, default to first event
                        if self.selectedEventId == nil {
                            self.selectedEventId = userData.events.first?.key
                        }
                    }
                } catch {
                    print("Token validation failed:", error)
                    await MainActor.run {
                        self.isAuthenticated = false
                        UserDefaults.standard.removeObject(forKey: "authToken")
                    }
                }
            }
        }
    }

    var selectedEvent: Event? {
        guard let eventId = selectedEventId ?? currentUser?.events.first?.key,
              let event = currentUser?.events[eventId] else {
            return currentUser?.events.first?.value
        }
        return event
    }

    private func createDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss"
        ].map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(abbreviation: "UTC")!  // Force UTC
            formatter.calendar = Calendar(identifier: .gregorian)  // Use gregorian calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")  // Use POSIX locale for consistency
            return formatter
        }
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        
        return decoder
    }

    func uploadProfilePicture(imageData: Data, token: String) async throws -> String {
        let url = URL(string: "\(baseURL)/changeProfilePicture")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"token\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(token)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"profilePicture\"; filename=\"profile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        let result = try JSONDecoder().decode(ProfilePictureResponse.self, from: data)
        return result.profilePictureUrl
    }

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
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw JSON response:", jsonString)
        }
        
        let decoder = createDecoder()
        let user = try decoder.decode(User.self, from: data)
        await MainActor.run {
            self.currentUser = user
        }
        return user
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

    func createCalendarEvent(eventId: String, calendarEventId: String, title: String, startTime: Date, endTime: Date, color: String) async throws -> APICalendarEvent {
        let url = URL(string: "\(baseURL)/createCalendarEvent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let requestBody = CreateCalendarEventRequest(
            token: token,
            eventId: eventId,
            calendarEventId: calendarEventId,
            title: title,
            startTime: startTime,
            endTime: endTime,
            color: color
        )
        
        request.httpBody = try encoder.encode(requestBody)
        if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
            print("Request body:", jsonString)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Response data:", jsonString)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                print("Server error:", errorJson.error)
            }
            throw AuthError.serverError
        }
        
        let decoder = createDecoder()
        let creationResponse = try decoder.decode(CreateCalendarEventResponse.self, from: data)
        
        return APICalendarEvent(
            id: creationResponse.id,
            title: creationResponse.title,
            startTime: creationResponse.startTime,
            endTime: creationResponse.endTime,
            color: creationResponse.color
        )
    }
    
    func updateCalendarEvent(calendarEventId: String, title: String?, startTime: Date?, endTime: Date?, color: String?) async throws -> PartialCalendarEventResponse {
        let url = URL(string: "\(baseURL)/updateCalendarEvent")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        var body: [String: Any] = ["token": token, "calendarEventId": calendarEventId]
        if let title = title { body["title"] = title }
        if let startTime = startTime { body["startTime"] = formatDate(startTime) }
        if let endTime = endTime { body["endTime"] = formatDate(endTime) }
        if let color = color { body["color"] = color }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("Request body:", String(data: request.httpBody!, encoding: .utf8) ?? "")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log the raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw API Response:", jsonString)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        print("Response status code:", httpResponse.statusCode)
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                print("Server error:", errorJson.error)
            }
            throw AuthError.serverError
        }
        
        do {
            let decoder = createDecoder()
            let response = try decoder.decode(PartialCalendarEventResponse.self, from: data)
            print("Successfully decoded response:", response)
            return response
        } catch {
            print("Decoding error:", error)
            print("Decoding error details:", (error as? DecodingError).map { "\($0)" } ?? "Unknown error")
            throw error
        }
    }
    
    func deleteCalendarEvent(calendarEventId: String) async throws {
        let url = URL(string: "\(baseURL)/deleteCalendarEvent")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let body = ["token": token, "calendarEventId": calendarEventId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func createEventTask(eventId: String, title: String, description: String, startTime: Date, endTime: Date, initialAssignee: String) async throws -> EventTask {
        let url = URL(string: "\(baseURL)/createEventTask")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let requestBody = [
            "token": token,
            "eventId": eventId,
            "title": title,
            "description": description,
            "startTime": formatDate(startTime),
            "endTime": formatDate(endTime),
            "initialAssignee": initialAssignee
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        let decoder = createDecoder()
        return try decoder.decode(EventTask.self, from: data)
    }

    func updateEventTask(
        taskId: String,
        title: String? = nil,
        description: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) async throws -> EventTask {
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let url = URL(string: "\(baseURL)/editEventTask")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var parameters: [String: Any] = ["token": token, "taskId": taskId]
        if let title = title { parameters["title"] = title }
        if let description = description { parameters["description"] = description }
        if let startTime = startTime { parameters["startTime"] = formatDate(startTime) }
        if let endTime = endTime { parameters["endTime"] = formatDate(endTime) }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw AuthError.serverError
        }
        
        // Use the custom decoder that handles different date formats
        let decoder = createDecoder()
        return try decoder.decode(EventTask.self, from: data)
    }

    func deleteEventTask(taskId: String) async throws {
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let url = URL(string: "\(baseURL)/deleteEventTask")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters = ["token": token, "taskId": taskId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw AuthError.serverError
        }
    }

    func assignEventTask(taskId: String, assigneeEmail: String) async throws -> EventTask {
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let url = URL(string: "\(baseURL)/assignEventTask")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "token": token,
            "taskId": taskId,
            "assigneeEmail": assigneeEmail
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw AuthError.serverError
        }
        
        let decoder = createDecoder()
        return try decoder.decode(EventTask.self, from: data)
    }

    func unassignEventTask(taskId: String, userEmailToRemove: String) async throws -> EventTask {
        guard let token = UserDefaults.standard.string(forKey: "authToken") else {
            throw AuthError.invalidToken
        }
        
        let url = URL(string: "\(baseURL)/unassignEventTask")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "token": token,
            "taskId": taskId,
            "userEmailToRemove": userEmailToRemove
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw AuthError.serverError
        }
        
        let decoder = createDecoder()
        return try decoder.decode(EventTask.self, from: data)
    }

    func refreshCalendarEvents() {
        print("\n=== Refreshing Calendar Events ===")
        objectWillChange.send()
        
        // Re-assign currentUser to force state update
        if let user = currentUser {
            currentUser = user
            
            // Notify any listening views that they should update
            NotificationCenter.default.post(name: NSNotification.Name("RefreshCalendarEvents"), object: nil)
        }
        print("Calendar events refreshed")
        print("===========================\n")
    }

    func updateCalendarEventInState(eventId: String, calendarEventId: String, updates: (inout APICalendarEvent) -> Void) {
        print("--- State Update Debug ---")
        print("Before update:")
        print("Current user events:", currentUser?.events.keys.joined(separator: ", ") ?? "nil")
        print("Selected event ID:", selectedEventId ?? "nil")
        print("Selected event calendar events:", selectedEvent?.calendarEvents.map { $0.id }.joined(separator: ", ") ?? "nil")
        
        if var user = currentUser,
           var selectedEvent = user.events[eventId] {
            if let calendarEventIndex = selectedEvent.calendarEvents.firstIndex(where: { 
                $0.id.lowercased() == calendarEventId.lowercased() 
            }) {
                print("\nFound calendar event at index:", calendarEventIndex)
                print("Before color:", selectedEvent.calendarEvents[calendarEventIndex].color)
                
                // Apply the updates
                updates(&selectedEvent.calendarEvents[calendarEventIndex])
                
                print("After color:", selectedEvent.calendarEvents[calendarEventIndex].color)
                
                // Update the event in the user's dictionary
                user.events[eventId] = selectedEvent
                
                // Force a complete state refresh
                objectWillChange.send()
                
                // Update the currentUser to trigger UI refresh
                currentUser = nil  // Force a clean state
                currentUser = user // Reassign to trigger update
                
                // Force selectedEvent to update by toggling selectedEventId
                if let currentEventId = selectedEventId {
                    selectedEventId = nil
                    selectedEventId = currentEventId
                }
                
                print("\nAfter update:")
                print("Updated event calendar events:", selectedEvent.calendarEvents.map { $0.id }.joined(separator: ", "))
                print("Current selected event calendar events:", self.selectedEvent?.calendarEvents.map { $0.id }.joined(separator: ", ") ?? "nil")
                
                // Notify any listening views that they should update
                NotificationCenter.default.post(
                    name: NSNotification.Name("RefreshCalendarEvents"), 
                    object: nil,
                    userInfo: ["eventId": eventId, "calendarEventId": calendarEventId]
                )
            } else {
                print("\nError: Could not find calendar event with ID:", calendarEventId)
                print("Available IDs:", selectedEvent.calendarEvents.map { $0.id })
            }
        } else {
            print("\nError: Could not find user or selected event")
            print("User exists:", currentUser != nil)
            print("Event ID exists:", eventId)
        }
        print("------------------------")
    }
}
