//
//  Extensions.swift
//  SceneManager
//
//  Created by Hans Kröner on 27/04/2025.
//

import SwiftUI

// MARK: - GradientError

enum GradientError: Error {
    case percentNotInGradient(percent: Double)
    case colorNotInGradient(color: NSColor)
}

extension GradientError: CustomStringConvertible {
    var description: String {
        switch self {
        case .percentNotInGradient(let percent):
            return "'\(percent)' does not have a transition."

        case .colorNotInGradient(let color):
            return "'\(color)' is not contained in the gradient."
        }
    }
}

// MARK: - NSColor

extension NSColor {
    func adjust(hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1) -> NSColor {
        var currentHue: CGFloat = 0
        var currentSaturation: CGFloat = 0
        var currentBrigthness: CGFloat = 0
        var currentAlpha: CGFloat = 0
        
        self.getHue(&currentHue, saturation: &currentSaturation, brightness: &currentBrigthness, alpha: &currentAlpha)
        
        return NSColor(hue: min(currentHue + hue, 1.0), saturation: min(currentSaturation + saturation, 1.0), brightness: min(currentBrigthness + brightness, 1.0), alpha: min(currentAlpha + alpha, 1.0))
    }
}

// MARK: - Color

extension Color {
    func adjust(hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1) -> Color {
        let color = NSColor(self).usingColorSpace(.sRGB)!
        
        return Color(color.adjust(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha).usingColorSpace(.sRGB)!)
    }
}

// MARK: - Double

extension Double {
    func convert(fromMin oldMin: Double, max oldMax: Double, toMin newMin: Double, max newMax: Double) -> Double {
        let oldRange, newRange, newValue: Double
        oldRange = (oldMax - oldMin)
        if (oldRange == 0.0) {
            newValue = newMin
        } else {
            newRange = (newMax - newMin)
            newValue = (((self - oldMin) * newRange) / oldRange) + newMin
        }
        return newValue
    }

    func convert(fromZeroToMax oldMax: Double, toZeroToMax newMax: Double) -> Double {
        return ((self * newMax) / oldMax)
    }
}
