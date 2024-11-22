//
//  Configuration.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/31/24.
//

import Foundation
import SwiftUI

enum Configuration {
    static let oneSignalAppId = "6b2176f5-c274-4521-9290-78da52da584d"
}

class TimelineConfiguration: ObservableObject {
    static let shared = TimelineConfiguration()
    
    static let minBlockHeight: CGFloat = 75.0
    static let maxBlockHeight: CGFloat = 250.0
    static let incrementSize: CGFloat = 15.0
    static let defaultHeight: CGFloat = 90.0
    
    private var lastHapticFeedback: CGFloat = 90.0
    private var fadeOutTimer: Timer?
    
    @Published private(set) var blockHeight: CGFloat
    @Published var isZooming: Bool = false
    
    private init() {
        // Load saved height from UserDefaults or use default
        self.blockHeight = UserDefaults.standard.double(forKey: "TimelineBlockHeight").cgFloat
        if self.blockHeight == 0 || self.blockHeight < Self.minBlockHeight || self.blockHeight > Self.maxBlockHeight {
            self.blockHeight = Self.defaultHeight
        }
    }
    
    func updateHeight(scale: CGFloat, initialHeight: CGFloat) {
        // Calculate new height based on scale and initial height
        var newHeight = initialHeight * scale
        
        // Round to nearest increment
        newHeight = round(newHeight / Self.incrementSize) * Self.incrementSize
        
        // Clamp between min and max
        newHeight = min(max(newHeight, Self.minBlockHeight), Self.maxBlockHeight)
        
        // Only update if the value has changed and is different from current
        if newHeight != blockHeight {
            // Provide haptic feedback at limits and increments
            if newHeight == Self.minBlockHeight || newHeight == Self.maxBlockHeight {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            } else if abs(newHeight - lastHapticFeedback) >= Self.incrementSize {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred(intensity: 0.5)
                lastHapticFeedback = newHeight
            }
            
            withAnimation(.interactiveSpring()) {
                blockHeight = newHeight
                isZooming = true
            }
            
            // Save to UserDefaults
            UserDefaults.standard.set(Double(newHeight), forKey: "TimelineBlockHeight")
            
            // Reset fade out timer
            fadeOutTimer?.invalidate()
            fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                withAnimation {
                    self?.isZooming = false
                }
            }
            
            NotificationCenter.default.post(
                name: NSNotification.Name("TimelineBlockHeightChanged"),
                object: nil
            )
        }
    }
    
    func resetToDefault() {
        updateHeight(scale: 1.0, initialHeight: Self.defaultHeight)
    }
}

// Helper extension to convert Double to CGFloat
extension Double {
    var cgFloat: CGFloat {
        CGFloat(self)
    }
}

