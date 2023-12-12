//
//  Token.swift
//  
//
//  Created by Gordon on 12.12.23.
//

import Foundation
import JWTDecode

struct Token {
    let token: String
    let expiresAt: Int
    
    init(token: String) {
        self.token = token
        
        do {
            let jwt = try decode(jwt: token)
            self.expiresAt = Int(jwt.expiresAt?.timeIntervalSince1970 ?? 0)
        } catch {
            self.expiresAt = 0
        }
    }
    
    init(token: String, expiresAt: Int) {
        self.token = token
        self.expiresAt = expiresAt
    }
}
