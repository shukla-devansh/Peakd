//  PreviewData.swift
//  In-memory stores for #Previews. Debug builds only.

#if DEBUG
import SwiftData

@MainActor
enum PreviewData {
    static func container(withProfile: Bool = true) -> ModelContainer {
        let container = try! CadenceStore.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try? ExerciseLibrary.seedIfNeeded(in: context)
        if withProfile {
            let profile = UserProfile()
            context.insert(profile)
            _ = try? StarterPlan.install(for: profile, in: context)
        }
        try? context.save()
        return container
    }
}
#endif
