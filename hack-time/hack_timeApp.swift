//
//  hack_timeApp.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/24/24.
//

import SwiftUI
import OneSignalFramework

@main
struct hack_timeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .preferredColorScheme(.light)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Remove this method to stop OneSignal Debugging
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        
        // OneSignal initialization
        OneSignal.initialize("6b2176f5-c274-4521-9290-78da52da584d", withLaunchOptions: launchOptions)

        // requestPermission will show the native iOS notification permission prompt.
        OneSignal.Notifications.requestPermission({ accepted in
            print("User accepted notifications: \(accepted)")
        }, fallbackToSettings: true)
            
        return true
    }
}
