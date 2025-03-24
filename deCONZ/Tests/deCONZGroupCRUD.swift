//
//  deCONZGroupCRUD.swift
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

struct deCONZGroupCRUD {
    
    private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "tests")
    private let client = deCONZ.RESTClient(apiKey: apiKey, apiURL: apiURL)
    
    private static var groupId: Int?

    @Test func testGroupCreate() async throws {
        let testGroupName = "Test Group"
        deCONZGroupCRUD.groupId = try await client.createGroup(name: testGroupName)
        logger.info("Created '\(testGroupName, privacy: .public)' with ID '\(deCONZGroupCRUD.groupId!, privacy: .public)'")
    }
    
    @Test func testGroupRename() async throws {
        guard let groupId = deCONZGroupCRUD.groupId else {
            Issue.record("Group ID not set")
            return
        }
        
        let testGroupName = "Group Test"
        try await client.setGroupAttributes(groupId: groupId, name: testGroupName)
        logger.info("Renamed group with ID '\(groupId, privacy: .public)' to '\(testGroupName, privacy: .public)'")
    }
    
    @Test func testGroupDelete() async throws {
        guard let groupId = deCONZGroupCRUD.groupId else {
            Issue.record("Group ID not set")
            return
        }
        
        try await client.deleteGroup(groupId: groupId)
        logger.info("Deleted group with ID '\(groupId, privacy: .public)'")
    }
}
