//
//  Main.swift
//  AccessibleText
//
//  Created by Morris Richman on 8/26/25.
//

import Foundation
import CryptoKit
import SwiftSyntaxMacros
import SwiftCompilerPlugin

extension String: @retroactive Error {
    func dropFirst(_ k: Int = 1) -> String {
        var str = self
        str.removeFirst(k)
        return str
    }
    func dropLast(_ k: Int = 1) -> String {
        var str = self
        str.removeLast(k)
        return str
    }
}

@main
struct AccessibleTextPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AccessibleTextMacro.self,
        AccessibleNavigationTitleMacro.self
    ]
}

func sha256(_ input: String) -> String {
  let inputData = Data(input.utf8)
  let hashedData = SHA256.hash(data: inputData)
  let hashString = hashedData.compactMap {
    String(format: "%02x", $0)
  }.joined()

  return hashString
}
