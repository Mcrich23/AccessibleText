import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import CryptoKit

/// A macro designed to help make static text more accessible by generating dynamically scaling text instead.
/// To use `accessibleText`, reference it in a `View` body with a static string.
/// - Note: While the string should be mostly static, you can use variables in it.
///
/// When you build your project, the compile script you added when setting up the macro will create/update `AccessibleTextContainer.swift` with text options for the string in your macro call.
///
/// - Note: This will not be modified unless you change the string in the macro. You can change the text options that were generated without any concern.
///
/// ## Example Use
///
///```swift
/// struct ContentView: View {
///    let name: String = "Morris"
///    let feature = "accessibility"
///    var body: some View {
///        VStack {
///            Image(systemName: "globe")
///                .imageScale(.large)
///                .foregroundStyle(.tint)
///            #accessibleText("Hi \(name)! I am testing \(feature)")
///        }
///        .padding()
///    }
///}
///```
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
        
        let hash = sha256(stringLiteral.description.dropFirst().dropLast())

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
