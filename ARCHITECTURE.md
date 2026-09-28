# Cookbook App Architecture

## Overview

The Cookbook app follows a clean MVVM (Model-View-ViewModel) architecture using SwiftUI and iCloud for storage, with built-in recipe sharing capabilities.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Views Layer                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│     │  RecipeList  │  │ RecipeDetail │  │  RecipeEdit  │    │
│     │     View     │→ │     View     │  │     View     │    │
│     └──────────────┘  └──────────────┘  └──────────────┘    │
│          ↓                 ↓                  ↓             │
│          │                 │                  │             │
│          └─────────────────┴──────────────────┘             │
│                            ↓                                │
│                     ┌─────────────┐                         │
│                     │ ShareSheet  │ (UI Helper)             │
│                     └─────────────┘                         │
│                                                             │
└────────────────────────────┼────────────────────────────────┘
                             ↓
                   @EnvironmentObject
                             ↓
┌────────────────────────────┼────────────────────────────────┐
│                      Services Layer                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│         ┌──────────────────┐      ┌──────────────────┐      │
│         │   RecipeStore    │      │ NFCRecipeSharer  │      │
│         │   (Observable)   │      │  (Observable)    │      │
│         └──────────────────┘      └──────────────────┘      │
│                 ↓                          ↓                │
│      ┌──────────┴──────────┐               ↓                │
│      ↓                     ↓          NFC Sessions          │
│  ┌──────────┐      ┌──────────┐          (iOS)              │
│  │  Local   │      │  iCloud  │                             │
│  │ Storage  │  ←→  │   Sync   │                             │
│  └──────────┘      └──────────┘                             │
│                            ↓                                │
└────────────────────────────┼────────────────────────────────┘
                             ↓
┌────────────────────────────┼────────────────────────────────┐
│                      Models Layer                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│      ┌────────────┐   ┌────────────┐   ┌────────────┐       │
│      │   Recipe   │   │ Ingredient │   │ Direction  │       │
│      │  (Codable) │   │  (Codable) │   │ (Codable)  │       │
│      └────────────┘   └────────────┘   └────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                             ↓
                    Stored as / Shared as
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                    Storage & Sharing                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  iCloud Drive / Documents / Recipes /                       │
│         ├── banana-bread-3f2504.md                          │
│         ├── chicken-tikka-masala-a81b2c.md                  │
│         └── weeknight-pasta-0c9e77.md                       │
│                                                             │
│  Shareable Format:                                          │
│         Recipe_Name.cookbook.json                           │
│         (Exported for sharing via AirDrop, iMessage, etc.)  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
CookbookApp/
├── Models/
│   └── Recipe.swift              # Data models
├── Services/
│   ├── RecipeStore.swift         # iCloud storage manager
│   └── NFCRecipeSharer.swift     # NFC sharing service (iOS)
├── Views/
│   ├── RecipeListView.swift      # Recipe list with search & import
│   ├── RecipeDetailView.swift    # Recipe display with share menu
│   ├── RecipeEditView.swift      # Recipe creation/editing
│   └── ShareSheet.swift          # Cross-platform share UI helper
├── CookbookApp.swift             # App entry point
└── Cookbook.entitlements         # iCloud & NFC configuration
```

## Component Descriptions

### Views Layer

#### RecipeListView
- **Purpose**: Homepage displaying all recipes
- **Features**: 
  - Searchable list
  - Recipe thumbnails with metadata
  - Navigation to detail view
  - Add new recipe
  - Swipe to delete
  - **Swipe to share** (new)
  - **Import recipes** from files (new)
  - Multi-file import support
- **State**: Observes RecipeStore

#### RecipeDetailView
- **Purpose**: Display full recipe information
- **Features**:
  - Recipe image
  - Checkable ingredients
  - Numbered directions
  - Metadata display
  - Mark as cooked
  - Edit navigation
  - **Share menu** with multiple options (new)
  - **NFC tap-to-share** on iOS (new)
- **State**: Receives recipe, observes store for updates

#### RecipeEditView
- **Purpose**: Create and edit recipes
- **Features**:
  - Photo picker
  - Form-based input
  - Dynamic ingredient/direction lists
  - Duration pickers
  - Rating selector
- **State**: Local state, saves to RecipeStore

#### ShareSheet
- **Purpose**: Cross-platform share UI wrapper
- **Type**: View helper (UIViewControllerRepresentable / NSViewRepresentable)
- **Features**:
  - iOS: Wraps UIActivityViewController
  - macOS: Wraps NSSharingServicePicker
  - Supports sharing recipe files via iMessage, AirDrop, Mail, etc.
- **Platform**: iOS & macOS

### Services Layer

#### RecipeStore (ObservableObject)
- **Purpose**: Single source of truth for recipe data
- **Responsibilities**:
  - Load recipes from iCloud
  - Save recipes to iCloud
  - Delete recipes
  - Maintain in-memory cache
  - Handle iCloud sync notifications
  - **Import recipes** from external files (new)
- **Published Properties**:
  - `recipes: [Recipe]` - Current recipe list
- **Platform**: iOS & macOS

#### NFCRecipeSharer (ObservableObject)
- **Purpose**: Manage NFC-based recipe sharing
- **Responsibilities**:
  - Initialize NFC reader sessions
  - Encode recipes to NDEF format
  - Write recipe data to NFC tags/devices
  - Handle NFC session lifecycle
  - Provide status updates
- **Published Properties**:
  - `isSharing: Bool` - Current sharing state
  - `statusMessage: String` - User-facing status
- **Platform**: iOS only (requires NFC-capable device)
- **Note**: Primarily for writing to NFC tags; for device-to-device sharing, AirDrop is more practical

### Models Layer

#### Recipe
- **Purpose**: Core data model
- **Properties**:
  - `id: UUID` - Unique identifier
  - `title: String` - Recipe name
  - `imageData: Data?` - Photo data
  - `ingredients: [Ingredient]` - List of ingredients
  - `directions: [Direction]` - Ordered steps
  - `dateCreated: Date` - Creation timestamp
  - `datesCooked: [Date]` - Cooking history
  - `sourceURL: String` - Origin link
  - `rating: Int` - 0-5 stars
  - `prepDuration: TimeInterval` - Prep time
  - `cookDuration: TimeInterval` - Cook time
  - `notes: String` - Additional notes
- **Conformance**: Identifiable, Codable
- **Sharing**: Fully serializable to JSON for sharing

#### Ingredient
- **Purpose**: Individual ingredient with checkbox state
- **Properties**:
  - `id: UUID`
  - `text: String`
  - `isChecked: Bool`
- **Conformance**: Identifiable, Codable

#### Direction
- **Purpose**: Ordered cooking step
- **Properties**:
  - `id: UUID`
  - `text: String`
  - `order: Int`
- **Conformance**: Identifiable, Codable

## Data Flow

### Creating a Recipe

```
User Input → RecipeEditView → RecipeStore.saveRecipe()
                                    ↓
                           JSONEncoder.encode()
                                    ↓
                           Write to iCloud file
                                    ↓
                           Update @Published recipes
                                    ↓
                           Views automatically refresh
```

### Loading Recipes

```
App Launch → RecipeStore.init()
                  ↓
           setupiCloudDirectory()
                  ↓
           loadRecipes()
                  ↓
      Read iCloud directory
                  ↓
      For each .json file:
      - JSONDecoder.decode()
      - Add to recipes array
                  ↓
      Sort alphabetically
                  ↓
      @Published triggers view update
```

### Sharing a Recipe

```
User selects share → RecipeDetailView/RecipeListView
                              ↓
                     Create temp .cookbook.json file
                              ↓
                     JSONEncoder.encode(recipe)
                              ↓
                     Write to temporary directory
                              ↓
                     ShareSheet presents options
                              ↓
              ┌───────────────┴───────────────┐
              ↓                               ↓
        Native Share                    NFC Share (iOS)
    (iMessage, AirDrop, etc.)           NFCRecipeSharer
              ↓                               ↓
      System handles delivery          Write to NFC tag
              ↓                               ↓
      Recipient receives file          Tag can be read later
```

### Importing a Recipe

```
Receive .cookbook.json file
        ↓
User taps file / selects import
        ↓
RecipeListView.handleImport()
        ↓
Read file with security scoped access
        ↓
JSONDecoder.decode(Recipe)
        ↓
Generate new UUID (avoid conflicts)
        ↓
Reset dateCreated and cooking state
        ↓
RecipeStore.saveRecipe()
        ↓
Recipe appears in list
```

### Syncing via iCloud

```
Device A: Save recipe
       ↓
iCloud uploads .json file
       ↓
iCloud syncs to Device B
       ↓
NSUbiquitousKeyValueStore notification
       ↓
Device B: RecipeStore.iCloudDataChanged()
       ↓
RecipeStore.loadRecipes()
       ↓
UI updates automatically
```

## Storage & Sharing Strategy

### Why Flat Files?

1. **Simplicity**: Easy to understand and debug
2. **Portability**: JSON is universal
3. **Backup-friendly**: Simple to export/import
4. **iCloud Integration**: Works seamlessly with CloudDocuments
5. **No Dependencies**: No database framework needed
6. **Shareable**: Direct file sharing without server infrastructure

### File Naming Convention

**Storage (iCloud):**
- Files named `<kebab-case-title>-<hash>.md`, e.g. `chipotle-chicken-burrito-bowls-3f2504.md`
- Human-legible when browsing the folder in Finder / Files
- The 6-character hash is the start of the recipe's UUID, so two recipes with the same title never collide and the name is stable across devices
- The recipe's identity is the `id` in the file's front matter, not the filename; renaming the title just renames the file
- Legacy `[UUID].json` and `[UUID].md` files are migrated to the new name on load (see `RecipeFileNaming`)

**Sharing (Export):**
- Files named with recipe title: `Recipe_Title.cookbook.json`
- Human-readable filenames
- Custom `.cookbook.json` extension for file type association
- Automatic opening in Cookbook app

### Sync vs. Share

| Aspect | iCloud Sync | Recipe Sharing |
|--------|-------------|----------------|
| **Scope** | User's own devices | Between different users |
| **Method** | Automatic via iCloud | Manual via share sheet/NFC |
| **File Location** | Private iCloud container | Temporary files / Messages / AirDrop |
| **Conflicts** | Last-write-wins | Each user has independent copy |
| **Purpose** | Keep personal collection in sync | Share recipes like recipe cards |

### Sharing Philosophy

The app implements **copy-based sharing** (not collaborative):
- When you share a recipe, recipient gets their own independent copy
- Like passing a recipe card to a friend
- Each person can modify, rate, and track their own version
- No real-time collaboration or cloud sync between users
- Preserves flat-file simplicity while enabling social features

### Import Behavior

When importing a recipe:
- ✅ New UUID generated (prevents ID conflicts)
- ✅ Creation date set to import time
- ✅ All ingredients unchecked (fresh cooking state)
- ✅ Cooking history cleared (recipient starts fresh)
- ✅ All recipe content preserved (title, image, ingredients, directions, etc.)

## Cross-Platform Support

### Platform Abstraction

```swift
#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif
```

### Platform-Specific Features

| Feature | iOS | macOS |
|---------|-----|-------|
| PhotosPicker | ✅ | ✅ |
| Share Sheet | ✅ (UIActivityViewController) | ✅ (NSSharingServicePicker) |
| Recipe Import | ✅ | ✅ |
| NFC Sharing | ✅ (iPhone XR+) | ❌ |
| AirDrop | ✅ | ✅ |
| iMessage | ✅ | ✅ |

### Shared Business Logic
- All data models platform-agnostic
- RecipeStore works identically on both platforms
- Sharing logic abstracted via ShareSheet wrapper

## Sharing Implementation Details

### File Type Registration

**UTI Declaration:**
- Identifier: `com.yourname.cookbook.recipe`
- Conforms to: `public.json`, `public.data`
- Extension: `.cookbook.json`
- Role: Editor (app can view and create)

**Benefits:**
- Files automatically open in Cookbook app
- System recognizes recipe files
- Searchable in Spotlight
- Proper icons in Files app

### Security & Privacy

**Shared Data:**
- Only explicitly shared recipes
- No automatic sync between users
- Standard iOS file sharing security

**Private Data:**
- Each user's iCloud container is private
- Cooking history never shared
- Ingredient check states reset on import
- New UUIDs prevent any cross-user tracking

### Error Handling

**Import Errors:**
- Invalid JSON → User-friendly error alert
- Missing required fields → Graceful degradation
- File access denied → Security scoped resource handling
- Multiple files → Individual error tracking, continue processing others

**Share Errors:**
- File creation failure → Console logging, user notification
- NFC errors → Status messages to user
- Permission denied → System handles prompts

## Performance Considerations

### Memory Management
- Images stored as `Data` in memory
- Large images may impact performance
- Consider implementing image compression for shared recipes
- Temporary share files cleaned up by system

### File I/O
- Recipes cached in memory
- File reads only on app launch and sync
- Async file operations prevent UI blocking
- Import operations on background thread (security scoped access)

### Scalability
- Current design works well for 100-1000 recipes
- Import performance: O(n) where n = number of files
- Sharing: Single file operations, very fast
- For 10,000+ recipes, consider:
  - Pagination
  - Lazy loading
  - Database solution

## Security

### Data Privacy
- All data stored in user's private iCloud account
- No external servers
- Apple handles encryption
- Shared recipes are just JSON files (no sensitive data)

### Authentication
- iCloud authentication via Apple ID
- Automatic secure storage
- No separate login required

### Permissions Required
- **Photo Library**: For adding recipe images
- **NFC (iOS)**: For tap-to-share feature
- **iCloud Drive**: For recipe storage and sync

## Error Handling

### Storage Errors
- Logged to console
- Silent failures (user experience preserved)
- Import errors show user-facing alerts

### Sync Errors
- Automatic retry via iCloud
- No manual intervention needed

### Sharing Errors
- File creation failures logged
- NFC errors displayed to user
- Import validation with error messages

## Future Architecture Improvements

### Potential Enhancements
1. **CoreData Integration**: Better performance at scale
2. **CloudKit Sharing**: True collaborative recipes (alternative to flat files)
3. **Image Optimization**: Automatic compression before sharing
4. **Offline Mode**: Better offline handling
5. **Conflict Resolution**: Custom merge strategies for syncing
6. **Background Sync**: App refresh background tasks
7. **Search Indexing**: Spotlight integration for shared recipes
8. **Batch Export**: Share multiple recipes at once
9. **QR Codes**: Alternative sharing method
10. **Recipe Collections**: Group related recipes for sharing

### Sharing Enhancements
- Recipe collections/cookbooks that can be shared as a unit
- "Shared by" metadata tracking
- Recipe versioning for updates
- Import from recipe URLs
- Social features (optional cloud sync for families)

### Testing Strategy
1. **Unit Tests**: 
   - Model encoding/decoding
   - Import validation logic
   - Share file creation
2. **Integration Tests**: 
   - Storage operations
   - Import/export flows
3. **UI Tests**: 
   - User flows
   - Share sheet presentation
   - Import workflows
4. **Sync Tests**: 
   - Multi-device scenarios
   - iCloud sync behavior
5. **Share Tests**:
   - File format validation
   - Cross-platform compatibility
   - NFC on physical devices

## Design Patterns Used

- **MVVM**: Separation of concerns
- **Observer**: @Published and ObservableObject
- **Repository**: RecipeStore as data access layer
- **Singleton**: Single RecipeStore instance via @StateObject
- **Dependency Injection**: Via @EnvironmentObject
- **Adapter**: ShareSheet wraps platform-specific share UI
- **Facade**: NFCRecipeSharer simplifies NFC complexity
- **Strategy**: Different sharing methods (share sheet vs. NFC)

## Best Practices Implemented

1. ✅ SwiftUI property wrappers for state management
2. ✅ Codable for serialization
3. ✅ UUID for unique identifiers
4. ✅ Optional chaining for safety
5. ✅ Error handling with try-catch
6. ✅ Platform abstractions for cross-platform code
7. ✅ Proper separation of concerns
8. ✅ Observable pattern for reactive updates
9. ✅ Security-scoped resource access for file imports
10. ✅ Temporary file cleanup
11. ✅ User-facing error messages
12. ✅ Compiler directives for platform-specific code
13. ✅ File type registration for seamless UX

## Architecture Philosophy

The Cookbook app maintains a **minimalist, flat-file architecture** while adding modern sharing capabilities. The key principles:

1. **Simplicity First**: Flat files over complex databases
2. **User Control**: Explicit sharing, no automatic social features
3. **Privacy**: Each user's data is theirs alone
4. **Portability**: Recipes are just JSON files, easily backed up and shared
5. **Platform Native**: Use Apple's frameworks properly (iCloud, share sheets, NFC)
6. **No Lock-in**: Data remains accessible outside the app

The sharing features extend this philosophy: recipes are shared like physical recipe cards, maintaining independence while enabling social connection.
