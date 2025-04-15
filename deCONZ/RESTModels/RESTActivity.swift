//
//  RESTActivity.swift
//  deCONZ
//
//  Created by Hans Kröner on 15/04/2025.
//

// MARK: Activity Log

public enum RESTActivityOutcome: Codable {
    case success
    case failure(description: String)
}

public struct RESTActivityEntry: Codable {
    let timestamp: Date
    
    var outcome: RESTActivityOutcome
    let path: String
    
    var request: String?
    var response: String?
    
    init(path: String, request: String? = nil, response: String? = nil) {
        self.timestamp = Date()
        self.outcome = .success
        
        self.path = path
        
        self.request = request
        self.response = response
    }
}

public struct RESTActivity: Codable {
    private var _entries: [RESTActivityEntry]
    
    public var entries: [RESTActivityEntry] {
        get {
            return _entries.sorted(by: { $0.timestamp < $1.timestamp })
        }
    }
    
    public mutating func append(_ entry: RESTActivityEntry) {
        self._entries.append(entry)
    }
}
