import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import CryptoKit

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct AccessibleTextMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        
        guard let argument = node.arguments.first?.expression,
              let stringArg = argument.as(StringLiteralExprSyntax.self)?.segments.first?.description else {
            throw "accessibleText requires a string literal"
        }
        
        let hash = sha256(stringArg)
        
        // Build `AccessibleText.`<hash>``
        let base = ExprSyntax(IdentifierExprSyntax(identifier: .identifier("AccessibleText")))
        
        let member = MemberAccessExprSyntax(
            base: base,
            dot: .periodToken(),
            name: .identifier("`\(hash)`") // backticks for safe identifier
        )
        
        return ExprSyntax(member)
    }
}

extension String: @retroactive Error {}

@main
struct AccessibleTextPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AccessibleTextMacro.self,
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
