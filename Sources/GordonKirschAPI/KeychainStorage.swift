//
//  KeychainStorage.swift
//
//
//  Created by Gordon on 12.12.23.
//

import Foundation
import KeychainSwift

class KeychainStorage {
    static let shared = KeychainStorage()
    private let keychain = KeychainSwift()
    
    func saveToken(response: LoginResponse) {
        keychain.set(response.accessToken, forKey: "accessToken")
        keychain.set(response.refreshToken, forKey: "refreshToken")
    }
    
    func clearTokens() {
        keychain.delete("accessToken")
        keychain.delete("refreshToken")
    }
    
    func getAccessToken() -> Token {
        return Token(token: keychain.get("accessToken") ?? "")
    }
    
    func getRefreshToken() -> Token {
        return Token(token: keychain.get("refreshToken") ?? "", expiresAt: 0)
    }
}
