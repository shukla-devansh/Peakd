//  CadenceApp.swift

import OSLog
import SwiftData
import SwiftUI

@main
struct CadenceApp: App {
    private let container: ModelContainer
    @State private var appState = AppState()

    init() {
        do {
            container = try CadenceStore.makeContainer()
        } catch {
            // A store that can't open (e.g. a schema change during development) shouldn't brick the app.
            Logger.app.error("Persistent store failed, using in-memory store: \(error.localizedDescription)")
            do {
                container = try CadenceStore.makeContainer(inMemory: true)
            } catch {
                fatalError("Could not create even an in-memory SwiftData store: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .task { await seedExerciseLibrary() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func seedExerciseLibrary() async {
        do {
            let inserted = try ExerciseLibrary.seedIfNeeded(in: container.mainContext)
            if inserted > 0 { Logger.app.info("Seeded \(inserted) exercises") }
        } catch {
            Logger.app.error("Exercise library seed failed: \(error.localizedDescription)")
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Cadence", category: "app")
}
