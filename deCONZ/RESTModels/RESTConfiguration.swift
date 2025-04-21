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
