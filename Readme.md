# AccessibleText
A macro designed to help make static text more accessible by generating dynamically scaling text instead.

## Installing The Package

### Xcode
Go to File > Add Package Dependencies and paste in [https://github.com/Mcrich23/AccessibleText.git](https://github.com/Mcrich23/AccessibleText.git) and add the `AccessibleText` framework to your target.

### Swift Package Manager

Add the following to the `dependencies` section of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mcrich23/AccessibleText.git", from: "1.0.0")
]
```

Then add `AccessibleText` to your target dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "AccessibleText", package: "AccessibleText")
        ]
    )
]
```

## Setup the Macro
Before you can use this macro, you have to set it up with the project.

### Pull A Model
AccessibleText uses [LM Studio](https://lmstudio.ai). It will use `qwen3:4b` unless otherwise specified with the environment variable `LM_STUDIO_MODEL`.

> Note: The model will automatically download if it is not already present on your machine.

### Add The Compile Script
1. Go to your target's `Build Phases` tab and create a new `Run Script` phase.
2. Drag the phase to be above your `Compile Sources` phase
3. Uncheck `Based on dependency analysis`
4. Paste in the following code

```bash
base_url="$(echo "$BUILT_PRODUCTS_DIR" | sed -E 's|(.*DerivedData/[^/]+).*|\1|')"

bash "$base_url/SourcePackages/checkouts/AccessibleText/Scripts/text-gen.sh" "$SRCROOT/<Target Folder>"
```
5. Replace `<Target Folder>` with the folder that contains the code for the target.

### Disable User Scripting Sandbox
The run phase references the shell script from this package's source files and then creates a file in your project. To do this, you must disable `User Scripting Sandbox`.

1. Go to your target's `Build Settings` tab
2. Filter for `User Scripting Sandbox`
3. Set `User Scripting Sandbox` to `No`

## Using the Macros

### #accessibleText
`accessibleText` is a dynamic text scaler for SwiftUI. To use `accessibleText`, reference it in a `View` body with a static string.

> Note: While the string should be mostly static, you can use variables in it.

When you build your project, the compile script you added when setting up the macro will create/update `AccessibleTextContainer.swift` with text options for the string in your macro call.

> Note: This will not be modified unless you change the string in the macro. You can change the text options that were generated without any concern.

#### Example Use

```swift
struct ContentView: View {
    let name: String = "Morris"
    let feature = "accessibility"
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            #accessibleText("Hi \(name)! I am testing \(feature)")
        }
        .padding()
    }
}
```

### #accessibleNavigationTitle
`accessibleNavigationTitle` dynamically scales the `navigationTitle` for its contents. To use `accessibleNavigationTitle`, reference it in a `View` body with a static string.

> Note: While the string should be mostly static, you can use variables in it.

When you build your project, the compile script you added when setting up the macro will create/update `AccessibleTextContainer.swift` with text options for the string in your macro call.

> Note: This will not be modified unless you change the string in the macro. You can change the text options that were generated without any concern.

#### Example Use

```swift
 struct ContentView: View {
    let name: String = "Morris"
    let feature = "accessibility"
    var body: some View {
        #accessibleNavigationTitle("Hi \(name)! I am testing \(feature)", content: {
            ScrollView {
                VStack {
                    Image(systemName: "globe")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    #accessibleText("Hi \(name)! I am testing \(feature)")
                }
                .padding()
            }
        })
    }
}
```
