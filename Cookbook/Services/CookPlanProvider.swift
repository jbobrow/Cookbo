import Foundation
import CryptoKit
import Combine

/// Hands cook mode the best plan available for a recipe: the on-device
/// model's when it has run, the text-only plan until then. Refinement runs in
/// the background when a recipe page opens, a step at a time, so cook mode
/// improves in place. Plans are cached on this device, keyed by the recipe's
/// ingredients and steps, so an edit starts over.
@MainActor
final class CookPlanProvider: ObservableObject {
    static let shared = CookPlanProvider()

    @Published private(set) var plans: [UUID: CookPlan] = [:]
    private var keys: [UUID: String] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Bumping this drops every cached plan, e.g. after changing the prompt.
    private static let version = 6

    func plan(for recipe: Recipe) -> CookPlan {
        if keys[recipe.id] == Self.key(for: recipe), let plan = plans[recipe.id] {
            return plan
        }
        return CookPlanner.heuristicPlan(for: recipe)
    }

    /// Starts working out the plan for a recipe, if it isn't already known.
    func prepare(_ recipe: Recipe) {
        guard !recipe.directions.isEmpty else { return }
        let key = Self.key(for: recipe)
        if keys[recipe.id] == key, plans[recipe.id] != nil { return }

        tasks[recipe.id]?.cancel()
        keys[recipe.id] = key

        if let cached = loadCached(recipe.id, key: key) {
            plans[recipe.id] = cached
            if cached.source == .onDevice || !Self.canRefine { return }
        } else {
            plans[recipe.id] = CookPlanner.heuristicPlan(for: recipe)
        }

        guard Self.canRefine else {
            if let plan = plans[recipe.id] { saveCached(plan, id: recipe.id, key: key) }
            return
        }
        refine(recipe, key: key)
    }

    private static var canRefine: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return OnDeviceCookPlanner.isAvailable
        }
        #endif
        return false
    }

    private func refine(_ recipe: Recipe, key: String) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return }
        let id = recipe.id
        let base = CookPlanner.heuristicPlan(for: recipe)
        let stepTexts = recipe.orderedDirections.map { $0.text.sanitizedForDisplay }
        let ingredientTexts = recipe.allIngredients.map(\.text)

        tasks[id] = Task { [weak self] in
            var plan = base
            var firstUse: [Int: Int] = [:]
            for index in plan.steps.indices {
                if Task.isCancelled { return }
                if let suggestion = await OnDeviceCookPlanner.suggest(step: index, of: recipe) {
                    plan.steps[index] = CookPlanner.merge(
                        suggestion,
                        into: plan.steps[index],
                        stepIndex: index,
                        stepTexts: stepTexts,
                        ingredientTexts: ingredientTexts,
                        firstUse: &firstUse
                    )
                } else {
                    for item in plan.steps[index].items where !item.isPrepared {
                        if let ingredient = item.ingredientIndex, firstUse[ingredient] == nil {
                            firstUse[ingredient] = index
                        }
                    }
                }
                guard let self, self.keys[id] == key, !Task.isCancelled else { return }
                self.plans[id] = plan
            }
            plan.source = .onDevice
            guard let self, self.keys[id] == key else { return }
            self.plans[id] = plan
            self.saveCached(plan, id: id, key: key)
            self.tasks[id] = nil
        }
        #endif
    }

    // MARK: - Cache

    private struct Stored: Codable {
        var key: String
        var plan: CookPlan
    }

    private static func key(for recipe: Recipe) -> String {
        var text = "v\(version)\n"
        text += recipe.allIngredients.map(\.text).joined(separator: "\n")
        text += "\n--\n"
        text += recipe.orderedDirections.map(\.text).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CookPlans", isDirectory: true)
    }

    private func loadCached(_ id: UUID, key: String) -> CookPlan? {
        guard let url = cacheDirectory?.appendingPathComponent("\(id.uuidString).json"),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.key == key else { return nil }
        return stored.plan
    }

    private func saveCached(_ plan: CookPlan, id: UUID, key: String) {
        guard let directory = cacheDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        if let data = try? JSONEncoder().encode(Stored(key: key, plan: plan)) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
