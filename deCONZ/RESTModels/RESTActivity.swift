//
//  RESTActivity.swift
//  deCONZ
//
//  Created by Hans Kröner on 15/04/2025.
//

import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "rest-activity")

// MARK: Activity Log

public enum RESTActivityOutcome: Codable {
    case success
    case failure(description: String)
}

public struct RESTActivityEntry: Identifiable, Codable {
    public let id = UUID()
    public let timestamp: Date
    
    public var outcome: RESTActivityOutcome
    public let path: String
    
    public var request: String?
    public var response: String?
    
    enum CodingKeys: CodingKey {
        case timestamp, outcome, path, request, response
    }
    
    public init(path: String, request: String? = nil, response: String? = nil) {
        self.timestamp = Date()
        self.outcome = .success
        
        self.path = path
        
        self.request = request
        self.response = response
    }
}

@Observable
public class RESTActivity {
    private var _entries: [RESTActivityEntry]
    
    public var entries: [RESTActivityEntry] {
        get {
            return _entries.sorted(by: { $0.timestamp > $1.timestamp })
        }
    }
    
    public init() {
        self._entries = []
    }
    
    public func append(_ entry: RESTActivityEntry) {
        self._entries.append(entry)
    }
}
