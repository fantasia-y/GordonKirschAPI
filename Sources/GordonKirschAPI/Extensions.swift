//
//  File.swift
//
//
//  Created by Gordon on 12.12.23.
//

import Foundation
import JWTDecode

extension Date {
    func timestamp() -> Int {
        return Int(self.timeIntervalSince1970)
    }
}

extension HTTPURLResponse {
    func isSuccessful() -> Bool {
        return statusCode >= 200 && statusCode <= 299
    }
}

extension URL {
    func extractParams() -> [(name: String, value: String)] {
      let components =
        self.absoluteString
        .split(separator: "&")
        .map { $0.split(separator: "=") }

      return
        components
        .compactMap {
          $0.count == 2
            ? (name: String($0[0]), value: String($0[1]))
            : nil
        }
    }
}
