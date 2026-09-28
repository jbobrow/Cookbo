import Foundation

/// The example recipe every new cookbook starts with, so the first screen has
/// something real to open, cook from, and edit.
///
/// Adapted from Caramelized Tomato and Shallot Soup on NYT Cooking. The
/// ingredients, method and photograph are theirs; the step wording here is our
/// own, and `sourceURL` points back to the full recipe.
enum SampleRecipe {

    static let title = "Caramelized Tomato and Shallot Soup"

    static let sourceURL = "https://cooking.nytimes.com/recipes/1025808-caramelized-tomato-and-shallot-soup"

    /// Fixed, so that if two devices ever both seed the sample into the same
    /// iCloud cookbook, the copies are one recipe rather than a duplicate.
    static let id = UUID(uuidString: "C00CB0DE-5A3F-4E1C-9B7A-7E0A7010500B")!

    private static let imageResource = "sample-recipe"

    /// The photo shipped in the app bundle. Nil if the resource is ever missing,
    /// which just leaves the recipe without an image.
    private static var imageData: Data? {
        guard let url = Bundle.main.url(forResource: imageResource, withExtension: "jpg") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func make() -> Recipe {
        Recipe(
            id: id,
            title: title,
            imageData: imageData,
            ingredients: [
                Ingredient(text: "1/4 cup extra-virgin olive oil, plus more for serving"),
                Ingredient(text: "1 pound shallots, halved and thinly sliced (about 4 cups)"),
                Ingredient(text: "3 pounds tomatoes, cored and chopped (about 6 cups)"),
                Ingredient(text: "Kosher salt and black pepper"),
                Ingredient(text: "3 large garlic cloves, minced"),
                Ingredient(text: "1 tsp sugar"),
                Ingredient(text: "1/4 cup tomato paste"),
                Ingredient(text: "1/2 packed cup fresh basil leaves, plus more for serving"),
                Ingredient(text: "1/4 cup heavy cream (optional)")
            ],
            directions: [
                Direction(text: "Warm the olive oil in a Dutch oven or heavy pot over medium heat. Add the shallots and cook until soft, jammy and caramelized, 20 to 25 minutes, stirring now and then and turning the heat down if the edges start to crisp.", order: 1),
                Direction(text: "While the shallots cook, set a colander over a large bowl and add the chopped tomatoes. Toss them with 1 teaspoon salt and leave them to drain, tossing again every so often to draw out as much liquid as they'll give. Keep the liquid in the bowl — you'll need it in step 6.", order: 2),
                Direction(text: "Once the shallots are caramelized, add the drained tomatoes to the pot along with the garlic and sugar.", order: 3),
                Direction(text: "Keep cooking over medium heat, stirring often and scraping the bottom, until the tomato juices in the pan have cooked down and the mixture starts to brown on the bottom, about 20 minutes.", order: 4),
                Direction(text: "Stir in the tomato paste and cook another 5 to 10 minutes, until everything is thick and caramelized and there are brown patches on the bottom of the pan.", order: 5),
                Direction(text: "Top up the reserved tomato liquid with water to make 3 cups total, then pour it into the pot. Stir in the basil and 1/2 teaspoon salt, scraping the caramelized bits off the bottom. Bring to a simmer, then purée with an immersion blender until it's as smooth as you like it.", order: 6),
                Direction(text: "Stir in the cream, if you're using it, and season with salt and pepper. Serve warm, with a drizzle of olive oil and a few basil leaves on top.", order: 7)
            ],
            sourceURL: sourceURL,
            prepDuration: 15 * 60,
            cookDuration: 70 * 60,
            notes: """
                Give the tomatoes and shallots the time they ask for — the caramelizing is where all the flavor comes from, and most of it is hands-off.

                Recipe and photograph adapted from NYT Cooking; tap the source link above for the original. This is the sample recipe Cookbo starts you off with — edit it, cook it, or delete it once your own recipes are in.
                """
        )
    }
}
