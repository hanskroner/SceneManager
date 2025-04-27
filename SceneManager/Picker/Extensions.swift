//
//  Extensions.swift
//  SceneManager
//
//  Created by Hans Kröner on 27/04/2025.
//

import SwiftUI

// MARK: - NSColor

extension NSColor {
    struct RGBA {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        
        init(color: NSColor) {
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
    }

    var rgba: RGBA {
        return RGBA(color: self)
    }

    // Linear Interpolation
    class func lerp(from: RGBA, to: RGBA, percent: CGFloat) -> NSColor {
        let red = from.red + percent * (to.red - from.red)
        let green = from.green + percent * (to.green - from.green)
        let blue = from.blue + percent * (to.blue - from.blue)
        let alpha = from.alpha + percent * (to.alpha - from.alpha)
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    class func miredDistance(lhs: NSColor, rhs: NSColor) -> CGFloat {
        let lhsMired = mired(fromColor: lhs)
        let rhsMired = mired(fromColor: rhs)
        
        return CGFloat(abs(lhsMired - rhsMired))
    }
    
    class func hueDistance(lhs: NSColor, rhs: NSColor) -> CGFloat {
        return abs(lhs.hueComponent - rhs.hueComponent)
    }
    
    func adjust(hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1) -> NSColor {
        var currentHue: CGFloat = 0
        var currentSaturation: CGFloat = 0
        var currentBrigthness: CGFloat = 0
        var currentAlpha: CGFloat = 0
        
        self.getHue(&currentHue, saturation: &currentSaturation, brightness: &currentBrigthness, alpha: &currentAlpha)
        
        return NSColor(hue: min(currentHue + hue, 1.0), saturation: min(currentSaturation + saturation, 1.0), brightness: min(currentBrigthness + brightness, 1.0), alpha: min(currentAlpha + alpha, 1.0))
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
