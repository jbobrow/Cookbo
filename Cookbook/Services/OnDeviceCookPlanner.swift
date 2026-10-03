import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// Asks Apple's on-device model to read one recipe step: a shorter version
/// for reading at a glance, the ingredients it uses, and anything carried
/// over from an earlier step. `CookPlanner.merge` checks the answer against
/// the recipe text before any of it is shown.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
enum OnDeviceCookPlanner {

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func suggest(step index: Int, of recipe: Recipe) async -> SuggestedStep? {
        let steps = recipe.orderedDirections
        guard steps.indices.contains(index) else { return nil }

        let ingredients = recipe.allIngredients.enumerated()
            .map { "\($0.offset + 1). \($0.element.text.sanitizedForDisplay)" }
            .joined(separator: "\n")
        let directions = steps.enumerated()
            .map { "\($0.offset + 1). \($0.element.text.sanitizedForDisplay)" }
            .joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You prepare recipe steps for a cook mode screen that someone reads from across the kitchen while their hands are busy.
            Use only what the recipe says. Never add or change ingredients, amounts, times, temperatures or steps.
            A good rewrite is a few short, direct sentences. It keeps what to do, the heat, how to tell it's done, and every number. It drops asides and filler words.
            For example, "Warm the butter in a large skillet over medium heat. Add the onions and cook, stirring now and then, until they are soft and golden, 10 to 12 minutes, lowering the heat if they start to scorch." becomes "Warm the butter over medium heat. Add the onions and cook until soft and golden, 10 to 12 minutes. Lower the heat if they scorch."
            """)

        let wordCount = steps[index].text.split(whereSeparator: \.isWhitespace).count
        let wordLimit = max(10, wordCount * 3 / 5)

        let prompt = """
            Recipe: \(recipe.title)

            Ingredients:
            \(ingredients)

            Steps:
            \(directions)

            Now read only step \(index + 1), which says:
            "\(steps[index].text.sanitizedForDisplay)"

            1. Rewrite it in at most \(wordLimit) words so it is easy to read at a glance. Keep every number exactly as written, including amounts, times, temperatures and step numbers. Don't number the rewrite. If the step is already short, give an empty rewrite.
            2. List the ingredients from the numbered ingredient list that go into this step, with the amount this step uses if it says one.
            3. List anything made or set aside in an earlier step that this step uses, such as reserved liquid or drained vegetables.
            """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedCookStep.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let step = response.content
            #if DEBUG
            print("Cook mode: step \(index + 1) rewrite: \(step.rewrite.isEmpty ? "(none)" : step.rewrite)")
            #endif
            return SuggestedStep(
                shortText: step.rewrite,
                uses: step.ingredients.map {
                    SuggestedStep.Use(ingredientNumber: $0.ingredientNumber, amount: $0.amount, name: $0.name)
                },
                carryOvers: step.fromEarlierSteps.map {
                    SuggestedStep.CarryOver(name: $0.name, stepNumber: $0.stepNumber)
                }
            )
        } catch {
            #if DEBUG
            print("Cook mode: on-device model skipped step \(index + 1): \(error)")
            #endif
            return nil
        }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension OnDeviceCookPlanner {
    /// For the overview: a one-word name per step, an estimate where the step
    /// gives no time, and which earlier step it happens alongside.
    static func suggestOverview(for recipe: Recipe) async -> [OverviewHint]? {
        let steps = recipe.orderedDirections
        guard !steps.isEmpty else { return nil }
        let directions = steps.enumerated()
            .map { "\($0.offset + 1). \($0.element.text.sanitizedForDisplay)" }
            .joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You summarize recipes for a timeline that shows each step as one short bar.
            Use only what the recipe says.
            """)
        let prompt = """
            Recipe: \(recipe.title)

            Steps:
            \(directions)

            For each of the \(steps.count) steps, in order, give:
            - its stage: Prep (cutting, greasing a pan), Mix (stirring, whisking, blending, a batter or dough), Assemble (layering, filling, shaping), Cook (on the stove: sauté, fry, sear, heat), Simmer (hands-off on the stove: simmer, braise, boil), Bake (in the oven: bake, roast, broil), Grill, Rest (cool, rise, marinate), Chill (fridge or freezer) or Serve (garnish, plate, serve)
            - how many minutes it takes if the step doesn't say, as your best estimate; 0 if the step gives a time
            - the number of an earlier step it happens at the same time as, like a sauce made meanwhile or an oven preheating; 0 if none
            """
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedOverview.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let byStep = Dictionary(response.content.steps.map { ($0.stepNumber, $0) }, uniquingKeysWith: { first, _ in first })
            return steps.indices.map { index in
                guard let step = byStep[index + 1] else { return OverviewHint(word: "", minutes: 0, alongsideStep: 0) }
                return OverviewHint(word: step.word, minutes: step.minutes, alongsideStep: step.alongsideStep)
            }
        } catch {
            #if DEBUG
            print("Cook mode: on-device model skipped the overview: \(error)")
            #endif
            return nil
        }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
nonisolated struct GeneratedOverview {
    @Guide(description: "One entry per step, in order.")
    var steps: [GeneratedOverviewStep]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
nonisolated struct GeneratedOverviewStep {
    @Guide(description: "The step's number.")
    var stepNumber: Int

    @Guide(description: "The stage this step belongs to.", .anyOf(["Prep", "Mix", "Assemble", "Cook", "Simmer", "Bake", "Grill", "Rest", "Chill", "Serve"]))
    var word: String

    @Guide(description: "Estimated minutes if the step gives no time, otherwise 0.")
    var minutes: Int

    @Guide(description: "The number of an earlier step this happens at the same time as, or 0.")
    var alongsideStep: Int
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
nonisolated struct GeneratedCookStep {
    @Guide(description: "The step rewritten to be short and easy to read at a glance, keeping every number exactly as written. Empty if the step is already short.")
    var rewrite: String

    @Guide(description: "Ingredients from the numbered ingredient list that go into this step.")
    var ingredients: [GeneratedIngredientUse]

    @Guide(description: "Things made or set aside in an earlier step that this step uses. Empty if none.")
    var fromEarlierSteps: [GeneratedCarryOver]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
nonisolated struct GeneratedIngredientUse {
    @Guide(description: "The ingredient's number in the ingredient list.")
    var ingredientNumber: Int

    @Guide(description: "How much this step uses, such as 1 tsp, exactly as the recipe says it. Empty if the step does not say.")
    var amount: String

    @Guide(description: "A short name for the ingredient, such as kosher salt.")
    var name: String
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
nonisolated struct GeneratedCarryOver {
    @Guide(description: "What it is, in a few words, such as reserved tomato liquid.")
    var name: String

    @Guide(description: "The number of the step where it was made or set aside.")
    var stepNumber: Int
}
#endif
