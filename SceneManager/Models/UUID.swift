//
//  UUID.swift
//  SceneManager
//
//  Created by Hans Kröner on 17/04/2025.
//

import Foundation
import CryptoKit

extension UUID {
    public init?(namespace: String, input: String) {
        // Create a hash using SHA-1 - as per the UUID v5 spec
        // https://www.rfc-editor.org/rfc/rfc4122#section-4.3
        let hash = Insecure.SHA1.hash(data: Data((namespace + input).utf8))
        
        // Use the most-significant 128 bits of the hash set the fields
        // according to the spec. - they can be visualized easier here:
        // https://www.uuidtools.com/decode
        var truncatedHash = Array(hash.prefix(16))
        truncatedHash[6] &= 0x0F    // Clear version field
        truncatedHash[6] |= 0x50    // Set version to 5

        truncatedHash[8] &= 0x3F    // Clear variant field
        truncatedHash[8] |= 0x80    // Set variant to DCE 1.1
        
        // Compute the UUID
        guard let uuid = UUID(uuidString: NSUUID(uuidBytes: truncatedHash).uuidString) else { return nil }
        self = uuid
    }
}
