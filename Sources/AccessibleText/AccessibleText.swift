// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI

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
@available(iOS 16.0, *)
@freestanding(expression)
public macro accessibleText(_ key: LocalizedStringKey) -> AccessibleTexts = #externalMacro(
    module: "AccessibleTextMacros",
    type: "AccessibleTextMacro"
)

@available(iOS 16.0, *)
@freestanding(expression)
public macro accessibleNavigationTitle<Content: View>(_ key: LocalizedStringKey, @ViewBuilder content: () -> Content) -> AccessibleNavigationTitles<Content> = #externalMacro(
    module: "AccessibleTextMacros",
    type: "AccessibleNavigationTitleMacro"
)
