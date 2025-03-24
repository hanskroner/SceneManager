//
//  deCONZSceneCRUD.swift
//  deCONZTests
//
//  Created by Hans Kröner on 24/03/2025.
//

import Testing
import OSLog

@testable import deCONZ

private let apiKey = ProcessInfo.processInfo.environment["DECONZ_API_KEY"] ?? ""
private let apiURL = ProcessInfo.processInfo.environment["DECONZ_API_URL"] ?? ""

private let decoder = JSONDecoder()
private let encoder = JSONEncoder()

struct deCONZSceneCRUD {
    
    private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "tests")
    private let client = deCONZ.RESTClient(apiKey: apiKey, apiURL: apiURL)
    
    private static var groupId: Int?
    private static var sceneId: Int?

    @Test func testGroupCreate() async throws {
        let testGroupName = "Test Group"
        deCONZSceneCRUD.groupId = try await client.createGroup(name: testGroupName)
        logger.info("Created '\(testGroupName, privacy: .public)' with ID '\(deCONZSceneCRUD.groupId!, privacy: .public)'")
    }
    
    @Test func testSceneCreate() async throws {
        guard let groupId = deCONZSceneCRUD.groupId else {
            Issue.record("Group ID not set")
            return
        }
        
        let testSceneName = "Test Scene"
        deCONZSceneCRUD.sceneId = try await client.createScene(groupId: groupId, name: testSceneName)
        logger.info("Created '\(testSceneName, privacy: .public)' with ID '\(deCONZSceneCRUD.sceneId!, privacy: .public)' in group with ID '\(groupId, privacy: .public)'")
    }
    
    @Test func testSceneRename() async throws {
        guard let groupId = deCONZSceneCRUD.groupId else {
            Issue.record("Group ID not set")
            return
        }
        
        guard let sceneId = deCONZSceneCRUD.sceneId else {
            Issue.record("Scene ID not set")
            return
        }
        
        let testSceneName = "Scene Test"
        try await client.setSceneAttributes(groupId: groupId, sceneId: sceneId, name: testSceneName)
        logger.info("Renamed scene with ID '\(sceneId, privacy: .public)' in group with ID '\(groupId, privacy: .public)' to '\(testSceneName, privacy: .public)'")
    }
    
    @Test func testSceneDelete() async throws {
        guard let groupId = deCONZSceneCRUD.groupId else {
            Issue.record("Group ID not set")
            return
        }
        
        guard let sceneId = deCONZSceneCRUD.sceneId else {
            Issue.record("Scene ID not set")
            return
        }
        
        try await client.deleteScene(groupId: groupId, sceneId: sceneId)
        logger.info("Deleted scene with ID '\(sceneId, privacy: .public)' from group with ID '\(groupId, privacy: .public)'")
    }
    
    @Test func testGroupDelete() async throws {
        guard let groupId = deCONZSceneCRUD.groupId else {
            Issue.record("Group ID not set")
            return
        }
        
        try await client.deleteGroup(groupId: groupId)
        logger.info("Deleted group with ID '\(groupId, privacy: .public)'")
    }
}
