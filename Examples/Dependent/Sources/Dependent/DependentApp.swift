import SwiftUI

@main
struct DependentApp: App {
    var body: some Scene {
        WindowGroup("Dependent") {
            Text((try? String(contentsOf: Bundle.module.url(forResource: "Greeting", withExtension: "txt")!, encoding: .utf8)) ?? "?")
                .padding(40)
        }
    }
}
