import Foundation
import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

struct Recipe: Identifiable, Codable {
    var id: UUID
    var title: String
    var imageData: Data?    // In-memory only; excluded from new JSON files
    var imageName: String?  // Persisted reference to image file in Images/
    var ingredientSections: [IngredientSection]
    var directions: [Direction]
    var dateCreated: Date
    var datesCooked: [Date]
    var sourceURL: String
    var rating: Int // 0-5 stars
    var prepDuration: TimeInterval // in seconds
    var cookDuration: TimeInterval // in seconds
    var notes: String
    var categoryID: UUID?
    var dateLastViewed: Date?   // Drives the "Just viewed" row
    var isInThisWeek: Bool      // Membership in the This Week plan

    var allIngredients: [Ingredient] {
        ingredientSections.flatMap { $0.ingredients }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, imageData, imageName, ingredients, ingredientSections, directions
        case dateCreated, datesCooked, sourceURL, rating
        case prepDuration, cookDuration, notes, categoryID
        case dateLastViewed, isInThisWeek
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        imageData: Data? = nil,
        imageName: String? = nil,
        ingredients: [Ingredient] = [],
        ingredientSections: [IngredientSection]? = nil,
        directions: [Direction] = [],
        dateCreated: Date = Date(),
        datesCooked: [Date] = [],
        sourceURL: String = "",
        rating: Int = 0,
        prepDuration: TimeInterval = 0,
        cookDuration: TimeInterval = 0,
        notes: String = "",
        categoryID: UUID? = nil,
        dateLastViewed: Date? = nil,
        isInThisWeek: Bool = false
    ) {
        self.id = id
        self.title = title
        self.imageData = imageData
        self.imageName = imageName
        if let sections = ingredientSections {
            self.ingredientSections = sections
        } else {
            self.ingredientSections = ingredients.isEmpty ? [] : [IngredientSection(name: "", ingredients: ingredients)]
        }
        self.directions = directions
        self.dateCreated = dateCreated
        self.datesCooked = datesCooked
        self.sourceURL = sourceURL
        self.rating = rating
        self.prepDuration = prepDuration
        self.cookDuration = cookDuration
        self.notes = notes
        self.categoryID = categoryID
        self.dateLastViewed = dateLastViewed
        self.isInThisWeek = isInThisWeek
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        // Decode old inline imageData for migration; new files won't have this key
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        // Try ingredientSections first, fall back to legacy flat ingredients
        if let sections = try container.decodeIfPresent([IngredientSection].self, forKey: .ingredientSections) {
            ingredientSections = sections
        } else {
            let flatIngredients = try container.decode([Ingredient].self, forKey: .ingredients)
            ingredientSections = flatIngredients.isEmpty ? [] : [IngredientSection(name: "", ingredients: flatIngredients)]
        }
        directions = try container.decode([Direction].self, forKey: .directions)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        datesCooked = try container.decode([Date].self, forKey: .datesCooked)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        rating = try container.decode(Int.self, forKey: .rating)
        prepDuration = try container.decode(TimeInterval.self, forKey: .prepDuration)
        cookDuration = try container.decode(TimeInterval.self, forKey: .cookDuration)
        notes = try container.decode(String.self, forKey: .notes)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        dateLastViewed = try container.decodeIfPresent(Date.self, forKey: .dateLastViewed)
        isInThisWeek = try container.decodeIfPresent(Bool.self, forKey: .isInThisWeek) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        // imageData is NOT encoded — images are stored as separate files
        try container.encodeIfPresent(imageName, forKey: .imageName)
        try container.encode(ingredientSections, forKey: .ingredientSections)
        // Also write flat ingredients for backward compat with older app versions on iCloud
        try container.encode(allIngredients, forKey: .ingredients)
        try container.encode(directions, forKey: .directions)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(datesCooked, forKey: .datesCooked)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(rating, forKey: .rating)
        try container.encode(prepDuration, forKey: .prepDuration)
        try container.encode(cookDuration, forKey: .cookDuration)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encodeIfPresent(dateLastViewed, forKey: .dateLastViewed)
        if isInThisWeek {
            try container.encode(isInThisWeek, forKey: .isInThisWeek)
        }
    }

    var image: Image? {
        guard let imageData = imageData else { return nil }

        #if os(iOS)
        guard let uiImage = UIImage(data: imageData) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}

struct Ingredient: Identifiable, Codable {
    var id: UUID
    var text: String
    var isChecked: Bool

    init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

struct IngredientSection: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var ingredients: [Ingredient]
}

struct Direction: Identifiable, Codable {
    var id: UUID
    var text: String
    var order: Int
    var isCompleted: Bool

    init(id: UUID = UUID(), text: String, order: Int, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.order = order
        self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        order = try container.decode(Int.self, forKey: .order)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}

extension String {
    /// Replaces non-breaking spaces with regular spaces so SwiftUI Text can wrap.
    var sanitizedForDisplay: String {
        replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
