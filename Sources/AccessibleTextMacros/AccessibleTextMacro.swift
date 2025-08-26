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

        // Ensure there is at least one argument
        guard let argument = node.arguments.first?.expression else {
            throw "accessibleText requires at least one string literal argument"
        }

        // Make sure it is a string literal
        guard let stringLiteral = argument.as(StringLiteralExprSyntax.self) else {
            throw "accessibleText requires a string literal as the first argument"
        }

        // Extract the literal text for hashing
        let rawString = stringLiteral.segments.map { segment -> String in
            if let str = segment.as(StringSegmentSyntax.self) {
                return str.content.text
            } else {
                return "\\(...)" // placeholder for interpolation
            }
        }.joined()

        let hash = sha256(rawString)

        // Build the base: AccessibleTextContainer
        let base = ExprSyntax(IdentifierExprSyntax(identifier: .identifier("AccessibleTextContainer")))

        let member = MemberAccessExprSyntax(
            base: base,
            dot: .periodToken(),
            name: .identifier("`\(hash)`") // hash with backticks
        )

        // Collect interpolated expressions from the string literal
        let interpolations: [TupleExprElementSyntax] = stringLiteral.segments.flatMap { segment in
            if let interp = segment.as(ExpressionSegmentSyntax.self) {
                return interp.expressions.flatMap { syntax in
                    TupleExprElementSyntax(expression: syntax.expression)
                }
            } else {
                return []
            }
        }
        let commaSeparatedInterpolations: [TupleExprElementSyntax] = interpolations.flatMap { syntax in
            TupleExprElementSyntax(expression: syntax.expression, trailingComma: syntax == interpolations.last ? nil : .commaToken())
        }
            

        // Build function call with interpolations
        let callExpr = FunctionCallExprSyntax(
            calledExpression: ExprSyntax(member),
            leftParen: .leftParenToken(),
            argumentList: TupleExprElementListSyntax(commaSeparatedInterpolations),
            rightParen: .rightParenToken()
        )

        return ExprSyntax(callExpr)
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
