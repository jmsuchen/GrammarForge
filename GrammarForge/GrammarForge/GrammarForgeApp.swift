import SwiftUI

@main
struct GrammarForgeApp: App {
    @StateObject private var store = GrammarStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
