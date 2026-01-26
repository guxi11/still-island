//
//  Still_IslandApp.swift
//  Still Island
//
//  Created by zhangyuanyuan on 2026/1/25.
//

import SwiftUI
import SwiftData

@main
struct Still_IslandApp: App {
    let sharedModelContainer: ModelContainer
    
    init() {
        let schema = Schema([
            DisplaySession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            
            // Configure DisplayTimeTracker with the model container
            Task { @MainActor in
                DisplayTimeTracker.shared.configure(with: container)
                // Setup screen state observers for away time tracking
                DisplayTimeTracker.shared.setupScreenStateObservers()
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
