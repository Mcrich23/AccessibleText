//
//  Helpers.swift
//  AccessibleText
//
//  Created by Morris Richman on 8/26/25.
//

import Foundation
import SwiftUI

public struct AccessibleTexts: View, @MainActor ExpressibleByArrayLiteral {
    private let texts: [Text]
    
    public init(_ texts: [Text]) {
        self.texts = texts
    }
    
    public init(arrayLiteral elements: Text...) {
        self.texts = elements
    }
    
    public var body: some View {
        ViewThatFits {
            ForEach(self.texts, id: \.self) { text in
                text
            }
        }
    }
}

public struct AccessibleNavigationTitles<Content: View>: View {
    private let texts: [Text]
    @ViewBuilder private var content: Content
    
    public init(_ texts: [Text], @ViewBuilder content: () -> Content) {
        self.texts = texts
        self.content = content()
    }
    
    public var body: some View {
        ViewThatFits {
            ForEach(self.texts, id: \.self) { text in
                content
                    .navigationTitle(text)
            }
        }
    }
}

extension Text: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: self))
    }
}
