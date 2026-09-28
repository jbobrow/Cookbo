import Foundation

/// A filter across the cookbook: either everything, one of the smart
/// collections, or a single category.
enum RecipeCollection: Hashable, Identifiable {
    case all
    case recentlyAdded
    case thisWeek
    case favorites
    case category(UUID)

    var id: String {
        switch self {
        case .all: return "all"
        case .recentlyAdded: return "recentlyAdded"
        case .thisWeek: return "thisWeek"
        case .favorites: return "favorites"
        case .category(let id): return "category-\(id.uuidString)"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .thisWeek: return "calendar"
        case .favorites: return "star"
        case .category: return "folder"
        }
    }

    /// Title for the chip. Categories supply their own name, so they're nil here.
    var fixedTitle: String? {
        switch self {
        case .all: return "All"
        case .recentlyAdded: return "Recently Added"
        case .thisWeek: return "This Week"
        case .favorites: return "Favorites"
        case .category: return nil
        }
    }

    /// The smart collections, in the order they appear in the chip bar.
    static let smartCollections: [RecipeCollection] = [.recentlyAdded, .thisWeek, .favorites]
}

/// The rules behind the smart collections, kept in one place so they're easy
/// to find, change and test.
enum RecipeCollectionRules {

    /// How far back "Recently Added" reaches.
    static let recentlyAddedWindow: TimeInterval = 30 * 24 * 60 * 60

    /// A recipe is a favorite at this rating or above...
    static let favoriteRating = 4

    /// ...or once it's been cooked this many times.
    static let favoriteCookCount = 3

    static func isRecentlyAdded(_ recipe: Recipe, now: Date = Date()) -> Bool {
        now.timeIntervalSince(recipe.dateCreated) <= recentlyAddedWindow
    }

    static func isFavorite(_ recipe: Recipe) -> Bool {
        recipe.rating >= favoriteRating || recipe.datesCooked.count >= favoriteCookCount
    }

    /// Applies a collection's filter and its natural sort order.
    static func apply(_ collection: RecipeCollection, to recipes: [Recipe], now: Date = Date()) -> [Recipe] {
        switch collection {
        case .all:
            return recipes

        case .recentlyAdded:
            return recipes
                .filter { isRecentlyAdded($0, now: now) }
                .sorted { $0.dateCreated > $1.dateCreated }

        case .thisWeek:
            return recipes.filter { $0.isInThisWeek }

        case .favorites:
            return recipes
                .filter { isFavorite($0) }
                .sorted { lhs, rhs in
                    if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

        case .category(let categoryID):
            return recipes.filter { $0.categoryID == categoryID }
        }
    }
}
