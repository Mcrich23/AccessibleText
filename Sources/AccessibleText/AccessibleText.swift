// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
//@available(iOS 16.0, *)
//@freestanding(expression)
//public macro accessibleText(_ value: LocalizedStringKey) -> any View = #externalMacro(module: "AccessibleTextMacros", type: "AccessibleTextMacro")

@available(iOS 16.0, *)
@freestanding(expression)
public macro accessibleText(_ key: String) -> AccessibleTexts = #externalMacro(
    module: "AccessibleTextMacros",
    type: "AccessibleTextMacro"
)
