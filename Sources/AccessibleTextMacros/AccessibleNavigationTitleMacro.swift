import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// A macro designed to help make static NavigationTitles more accessible by generating dynamically scaling navigation titles instead.
/// To use `accessibleNavigationTitle`, reference it in a `View` body with a static string.
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
///        #accessibleNavigationTitle("Hi \(name)! I am testing \(feature)", content: {
///            ScrollView {
///                VStack {
///                    Image(systemName: "globe")
///                        .imageScale(.large)
///                        .foregroundStyle(.tint)
///                    #accessibleText("Hi \(name)! I am testing \(feature)")
///                }
///                .padding()
///            }
///        })
///    }
///}
///```
public struct AccessibleNavigationTitleMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        
        // Ensure there is at least one argument
        guard node.arguments.count >= 2 else {
            throw "accessibleText requires at least two arguments"
        }

        // Make sure it is a string literal
        guard let stringLiteral = node.arguments.first?.expression.as(StringLiteralExprSyntax.self) else {
            throw "accessibleText requires a string literal as the first argument"
        }

        // Make sure it is a string literal
        guard let viewBody = node.arguments.removingFirst().first?.expression.as(ClosureExprSyntax.self) else {
            throw "accessibleText requires a view body as the second argument"
        }
        
        let hash = sha256(stringLiteral.description.dropFirst().dropLast())

        // Build the base: AccessibleTextContainer
        let base = ExprSyntax(IdentifierExprSyntax(identifier: .identifier("AccessibleTextContainer")))

        let member = MemberAccessExprSyntax(
            base: base,
            dot: .periodToken(),
            name: .identifier("`\(hash)_navigationTitle`") // hash with backticks
        )

        // Collect interpolated expressions from the string literal
        let interpolations: [TupleExprElementSyntax] = stringLiteral.segments.flatMap { segment in
            if let interp = segment.as(ExpressionSegmentSyntax.self) {
                return interp.expressions.flatMap { syntax in
                    TupleExprElementSyntax(expression: syntax.expression, trailingComma: .commaToken())
                }
            } else {
                return []
            }
        }
        let interpolationWithViewBody = interpolations + [TupleExprElementSyntax(label: "content", expression: viewBody)]
            

        // Build function call with interpolations
        let callExpr = FunctionCallExprSyntax(
            calledExpression: ExprSyntax(member),
            leftParen: .leftParenToken(),
            argumentList: TupleExprElementListSyntax(interpolationWithViewBody),
            rightParen: .rightParenToken()
        )

        return ExprSyntax(callExpr)
    }
}
