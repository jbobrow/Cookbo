import XCTest

final class RecipeCollectionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func recipe(
        _ title: String,
        rating: Int = 0,
        cooked: Int = 0,
        daysAgo: Double = 0,
        thisWeek: Bool = false,
        category: UUID? = nil
    ) -> Recipe {
        Recipe(
            title: title,
            dateCreated: now.addingTimeInterval(-daysAgo * 86_400),
            datesCooked: Array(repeating: now, count: cooked),
            rating: rating,
            categoryID: category,
            isInThisWeek: thisWeek
        )
    }

    // MARK: - Recently Added

    func testRecentlyAdded_includesRecent() {
        XCTAssertTrue(RecipeCollectionRules.isRecentlyAdded(recipe("a", daysAgo: 3), now: now))
    }

    func testRecentlyAdded_excludesOlderThanWindow() {
        XCTAssertFalse(RecipeCollectionRules.isRecentlyAdded(recipe("a", daysAgo: 31), now: now))
    }

    func testRecentlyAdded_sortsNewestFirst() {
        let recipes = [
            recipe("oldest", daysAgo: 20),
            recipe("newest", daysAgo: 1),
            recipe("middle", daysAgo: 10),
            recipe("expired", daysAgo: 90)
        ]
        let result = RecipeCollectionRules.apply(.recentlyAdded, to: recipes, now: now)
        XCTAssertEqual(result.map(\.title), ["newest", "middle", "oldest"])
    }

    // MARK: - Favorites

    func testFavorites_fourStarsQualifies() {
        XCTAssertTrue(RecipeCollectionRules.isFavorite(recipe("a", rating: 4)))
    }

    func testFavorites_threeStarsDoesNot() {
        XCTAssertFalse(RecipeCollectionRules.isFavorite(recipe("a", rating: 3)))
    }

    func testFavorites_threeCooksQualifiesWithoutRating() {
        XCTAssertTrue(RecipeCollectionRules.isFavorite(recipe("a", cooked: 3)))
    }

    func testFavorites_twoCooksDoesNot() {
        XCTAssertFalse(RecipeCollectionRules.isFavorite(recipe("a", cooked: 2)))
    }

    func testFavorites_sortedByRatingThenTitle() {
        let recipes = [
            recipe("beta", rating: 5),
            recipe("cooked often", cooked: 4),
            recipe("alpha", rating: 5),
            recipe("ignored", rating: 1)
        ]
        let result = RecipeCollectionRules.apply(.favorites, to: recipes, now: now)
        XCTAssertEqual(result.map(\.title), ["alpha", "beta", "cooked often"])
    }

    // MARK: - This Week and categories

    func testThisWeek_onlyFlaggedRecipes() {
        let recipes = [recipe("in", thisWeek: true), recipe("out")]
        let result = RecipeCollectionRules.apply(.thisWeek, to: recipes, now: now)
        XCTAssertEqual(result.map(\.title), ["in"])
    }

    func testCategory_onlyMatchingRecipes() {
        let target = UUID()
        let recipes = [recipe("mine", category: target), recipe("theirs", category: UUID()), recipe("none")]
        let result = RecipeCollectionRules.apply(.category(target), to: recipes, now: now)
        XCTAssertEqual(result.map(\.title), ["mine"])
    }

    func testAll_passesEverythingThrough() {
        let recipes = [recipe("a"), recipe("b", daysAgo: 400)]
        XCTAssertEqual(RecipeCollectionRules.apply(.all, to: recipes, now: now).count, 2)
    }
}
