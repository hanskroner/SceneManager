//
//  RESTSConfiguration.swift
//  SceneManager
//
//  Created by Hans Kröner on 21/04/2025.
//

// MARK: Configuration

struct RESTConfiguration: Decodable {
    let whitelist: [String: RESTConfigurationWhitelist]
}

struct RESTConfigurationWhitelist: Decodable {
    let create_date: String
    let last_use_date: String
    let name: String
    
    private enum CodingKeys: String, CodingKey {
        case create_date = "create date"
        case last_use_date = "last use date"
        case name
    }
}

extension ConfigurationAPIKey {
    init (key: String, configuration: RESTConfigurationWhitelist) {
        self.key = key
        self.name = configuration.name
        
        // Dates are provided in UTC by the REST API
        let dateFormatter = ISO8601DateFormatter()
        let createdString = configuration.create_date + "+0000"
        let lastUsedString = configuration.last_use_date + "+0000"
        
        self.created = dateFormatter.date(from: createdString) ?? Date()
        self.lastUsed = dateFormatter.date(from: lastUsedString) ?? Date()
    }
}
