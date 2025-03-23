//
//  Colors.swift
//  Colors
//
//  Created by Hans Kröner on 09/11/2024.
//

import Testing
import OSLog
import AppKit

@testable import SceneManager

private func cct(fromMired mired: Int) -> CGFloat {
    return pow(10, 6) / CGFloat(mired)
}

struct ColorTest {
    
    private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "tests")

    @Test func testColorFromCT() async throws {
        let mired = 500
        let color = SceneManager.color(fromMired: mired)!.usingColorSpace(.sRGB)!
        let kelvin = cct(fromMired: mired)
        
        logger.info("\(mired, privacy: .public), \(kelvin, privacy: .public)K - r:\(color.redComponent, privacy: .public), g:\(color.greenComponent, privacy: .public), b:\(color.blueComponent, privacy: .public)")
    }

}
