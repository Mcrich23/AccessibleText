import Foundation
import AccessibleText
import SwiftUI

struct AccessibleTextContainer {
    static func `19270ea4f98808a63fbb99bc26a5ee6f0fe8df9c8182cf1d710b115d57250578`(_ args: any CVarArg...) -> AccessibleText.AccessibleTexts {
        [
            Text(String(format: "\"Hello, world!\"", arguments: args)),
            Text(String(format: "\"Hello", arguments: args)),
            Text(String(format: " world!\"", arguments: args)),
        ]
    }
}
