//
//  Initializers.swift
//  SceneManager
//
//  Created by Hans Kröner on 21/10/2023.
//

import Foundation
import OSLog

import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "preview-initializer")

extension Presets {
    convenience init(json: Data) {
        self.init()
        
        // Can't access self.decoder - it's private
        let decoder = JSONDecoder()
        
        do {
            self.groups = [PresetItemGroup(name: "Preview", presets: try decoder.decode([PresetItem].self, from: json))]
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
}

extension Sidebar {
    convenience init(json: Data) {
        self.init()
     
        let decoder = JSONDecoder()
        
        do {
            self.items = try decoder.decode([SidebarItem].self, from: json)
            
            // Sort the items and the items' items.
            self.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            for (item) in self.items.filter({ !($0.items.isEmpty) }) {
                item.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
}

extension Lights {
    convenience init(json: Data) {
        self.init()
     
        let decoder = JSONDecoder()
        
        do {
            self.items = try decoder.decode([LightItem].self, from: json)
            
            // Sort the items
            self.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        } catch {
            logger.error("\(error, privacy: .public)")
        }
        
//        do {
//            let groups = try decoder.decode([Group].self, from: json)
//            
//            groups.forEach { group in
//                var sceneData: [Int: [LightItem]] = [:]
//                group.scenes.forEach { scene in
//                    sceneData[scene.sceneId] = scene.lights.map { light in
//                        LightItem(lightID: light.lightId, name: light.name)
//                    }
//                }
//                self.sceneData[group.groupId] = sceneData
//            }
//            
//            // Sort the lights
//            self.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
//        } catch {
//            logger.error("\(error, privacy: .public)")
//        }
    }
}
