//
//  Colors.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

enum Gamut {
    case gamutA
    case gamutB
    case gamutC
    
    func getTriangle() -> [CGPoint] {
        switch self {
        case .gamutA: return [CGPoint(x: 0.704, y: 0.296), CGPoint(x: 0.2151,y: 0.7106), CGPoint(x: 0.138, y: 0.08)]
        case .gamutB: return [CGPoint(x: 0.675, y: 0.322), CGPoint(x: 0.4091, y: 0.518), CGPoint(x: 0.167, y: 0.04)]
        case .gamutC: return [CGPoint(x: 0.692, y:  0.308), CGPoint(x: 0.17, y: 0.7), CGPoint(x: 0.153, y:  0.048)]
        }
    }
}

// MARK: - Private Methods

private func crossProduct(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
    return point1.x * point2.y - point2.x * point1.y
}

private func dotProduct(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
    return point1.x * point2.x + point1.y * point2.y
}

private func distanceBetweenPoint(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
    let dx = point1.x - point2.x
    let dy = point1.y - point2.y
    return sqrt(pow(dx, 2) + pow(dy, 2))
}

private func isPointInGamut(point: CGPoint, gamut: Gamut) -> Bool {
    let gamutTriangle = gamut.getTriangle()
    let v1 = CGPoint(x: gamutTriangle[1].x - gamutTriangle[0].x, y: gamutTriangle[1].y - gamutTriangle[0].y)
    let v2 = CGPoint(x: gamutTriangle[2].x - gamutTriangle[0].x, y: gamutTriangle[2].y - gamutTriangle[0].y)
    
    let q = CGPoint(x: point.x - gamutTriangle[0].x, y: point.y - gamutTriangle[0].y)
    let s = crossProduct(q, v2) / crossProduct(v1, v2)
    let t = crossProduct(v1, q) / crossProduct(v1, v2)
    
    return (s >= 0.0) && (t >= 0.0) && (s + t <= 1.0)
}

private func closestPointToLine(lineStart: CGPoint, lineEnd: CGPoint, point: CGPoint) -> CGPoint {
    let ap = CGPoint(x: point.x - lineStart.x, y: point.y - lineStart.y)
    let ab = CGPoint(x: lineEnd.x - lineStart.x, y: lineEnd.y - lineStart.y)
    let ab2 = pow(ab.x, 2) + pow(ab.y, 2)
    let ap_ab = (ap.x * ab.x) + (ap.y * ab.y)
    var t = ap_ab / ab2
    
    if t < 0.0 {
        t = 0.0
    } else if t > 1.0 {
        t = 1.0
    }
    
    return CGPoint(x: lineStart.x + ab.x * t, y: lineStart.y + ab.y * t)
}

private func closestPointToPoint(point: CGPoint, gamut: Gamut) -> CGPoint {
    let gamutTriangle = gamut.getTriangle()
    let p_ab = closestPointToLine(lineStart: gamutTriangle[0], lineEnd: gamutTriangle[1], point: point)
    let p_ac = closestPointToLine(lineStart: gamutTriangle[2], lineEnd: gamutTriangle[0], point: point)
    let p_bc = closestPointToLine(lineStart: gamutTriangle[1], lineEnd: gamutTriangle[2], point: point)
    
    let d_ab = distanceBetweenPoint(point, p_ab)
    let d_ac = distanceBetweenPoint(point, p_ac)
    let d_bc = distanceBetweenPoint(point, p_bc)
    
    var lowest = d_ab
    var closestPoint = p_ab
    
    if d_ac < lowest {
        lowest = d_ac
        closestPoint = p_ac
    }
    
    if d_bc < lowest {
        lowest = d_bc
        closestPoint = p_bc
    }
    
    return CGPoint(x: closestPoint.x, y: closestPoint.y)
}

private func cctFromMired(mired: Int) -> CGFloat {
    return pow(10, 6) / CGFloat(mired)
}

private func xyFromCCT(cct: CGFloat) -> CGPoint? {
    var x: CGFloat = 0.0
    var y: CGFloat = 0.0
    
    switch cct {
    case 1667 ..< 2222:
        x = (-0.2661239 * pow(10, 9) / pow(cct, 3) -
              0.2343589 * pow(10, 6) / pow(cct, 2) +
              0.8776956 * pow(10, 3) / cct +
              0.179910)
        y = (-1.10638140 * pow(x, 3) -
              1.34811020 * pow(x, 2) +
              2.18555832 * x -
              0.20219683)
    case 2222 ..< 4000:
        x = (-0.2661239 * pow(10, 9) / pow(cct, 3) -
              0.2343589 * pow(10, 6) / pow(cct, 2) +
              0.8776956 * pow(10, 3) / cct + 0.179910)
        y = (-0.95494760 * pow(x, 3) -
              1.37418593 * pow(x, 2) +
              2.09137015 * x -
              0.16748867)
    case 4000 ... 25000:
        x = (-3.0258469 * pow(10, 9) / pow(cct, 3) +
              2.1070379 * pow(10, 6) / pow(cct, 2) +
              0.2226347 * pow(10, 3) / cct +
              0.24039)
        y = (3.08175800 * pow(x, 3) -
             5.87338670 * pow(x, 2) +
             3.75112997 * x -
             0.37001483)
    default:
        return nil
    }
    
    return CGPoint(x: x, y: y)
}

// MARK: - Public Methods

func xyFromColor(color: NSColor, gamut: Gamut = .gamutC) -> CGPoint {
    var r = CGFloat()
    var g = CGFloat()
    var b = CGFloat()
    color.getRed(&r, green: &g, blue: &b, alpha: nil)
    
    // sRGB (D65) gamma correction - inverse companding to get linear values
    r = (r > 0.03928) ? pow((r + 0.055) / 1.055, 2.4) : (r / 12.92)
    g = (g > 0.03928) ? pow((g + 0.055) / 1.055, 2.4) : (g / 12.92)
    b = (b > 0.03928) ? pow((b + 0.055) / 1.055, 2.4) : (b / 12.92)
    
    // sRGB (D65) matrix transformation
    // http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    let X = (0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b)
    let Y = (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b)
    let Z = (0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b)
    
    let cx = X / (X + Y + Z)
    let cy = Y / (X + Y + Z)
    
    var xy = CGPoint(x: cx, y: cy)
    if !isPointInGamut(point: xy, gamut: gamut) {
        xy = closestPointToPoint(point: xy, gamut: gamut)
    }
    
    return xy
}

func colorFromXY(point: CGPoint, brightness: CGFloat, gamut: Gamut = .gamutC) -> NSColor {
    var xy = point
    if !isPointInGamut(point: xy, gamut: gamut) {
        xy = closestPointToPoint(point: point, gamut: gamut)
    }
    
    let X = (brightness / xy.y) * xy.x
    let Y = brightness
    let Z = (brightness / xy.y) * (1.0 - xy.x - xy.y)
    
    // sRGB (D65) matrix transformation
    // http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    var r =  (3.2404542 * X) - (1.5371385 * Y) - (0.4985314 * Z)
    var g = (-0.9692660 * X) + (1.8760108 * Y) + (0.0415560 * Z)
    var b =  (0.0556434 * X) - (0.2040259 * Y) + (1.0572252 * Z)
    
    // sRGB (D65) gamma correction - companding to get non-linear values
    r = (r <= 0.00304) ? (12.92 * r) : (1.055 * pow(r, (1.0 / 2.4)) - 0.055)
    g = (g <= 0.00304) ? (12.92 * g) : (1.055 * pow(g, (1.0 / 2.4)) - 0.055)
    b = (b <= 0.00304) ? (12.92 * b) : (1.055 * pow(b, (1.0 / 2.4)) - 0.055)
    
    // Zero-out negative values
    r = max(0, r)
    g = max(0, g)
    b = max(0, b)
    
    // If there's a value greater than 1.0, weight all the components by it
    if let max = [r, g, b].max(), max > 1 {
        r = r / max
        g = g / max
        b = b / max
    }
    
    return NSColor(red: r, green: g, blue: b, alpha: 1.0)
}

func colorFromMired(mired: Int) -> NSColor? {
    guard let xy = xyFromCCT(cct: cctFromMired(mired: mired)) else { return nil }
    return colorFromXY(point: xy, brightness: 1.0, gamut: .gamutC)
}
