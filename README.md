# Cookbo - A Simple Recipe Manager

A clean, minimalist SwiftUI app for iOS, iPadOS, and macOS that manages multiple cookbooks with recipes stored as flat files, synced via iCloud or stored locally.

## Features

### Multi-Cookbook System
- **Manage Multiple Cookbooks**: Create and organize separate cookbooks for different purposes
- **Cookbook Switcher**: Easily switch between cookbooks with a visual picker
- **Cookbook Operations**:
  - Create new cookbooks
  - Rename existing cookbooks
  - Delete cookbooks (with confirmation)
  - Share entire cookbooks as `.cookbook` files
  - View recipe and category counts for each cookbook
- **Independent Data**: Each cookbook maintains its own recipes and categories

### Recipe Management
- **Picture**: Add a photo for each recipe
- **Ingredients Checklist**: Check off ingredients as you gather them with animated checkmarks
- **Step-by-Step Directions**: Numbered instructions for easy following
- **Category Assignment**: Organize recipes with color-coded categories
- **Metadata**:
  - Date created (automatic)
  - Cooking history (track every time you make it)
  - Last cooked date
  - Source URL (link to original recipe)
  - Star rating (0-5 stars)
  - Prep time (hours and minutes)
  - Cook time (hours and minutes)
  - Notes section
- **Mark as Cooked**: Celebrate completion with animations, reset ingredients, and track cooking date
- **Share Recipes**: Export individual recipes as `.cookbook.json` files

### Category System
- **Color-Coded Categories**: 10 predefined colors
- **Per-Cookbook Categories**: Each cookbook has its own category system
- **Category Management**: Create, edit, rename, and delete categories
- **Visual Organization**: Recipes grouped by category in list view

### User Interface
- **Adaptive Views**: Grid view for iPad/macOS, list view for iOS
- **Search**: Filter by recipe name or ingredients in real-time
- **Recipe Cards**: Beautiful grid layout with images, ratings, times, and cook counts
- **Recipe Rows**: Compact list view with thumbnails and key info
- **Minimalist Design**: Clean, uncluttered interface
- **iPad Optimized**: Touch-friendly spacing, popovers, and context menus
- **Cross-Platform**: Works seamlessly on iOS, iPadOS, and macOS
- **Dark Mode**: Full support for light and dark themes
- **Keyboard Shortcuts**: Command+N for new recipes on macOS

### Data Storage
- **Dual Storage Options**:
  - **iCloud Drive**: Automatic sync across all your devices (default)
  - **Local Storage**: Device-only storage option for users without iCloud
- **Flexible Setup**: Choose storage preference during initial setup
- **Visible Files**: Cookbook folder accessible in iCloud Drive for easy file management
- **Individual JSON Files**: Each recipe stored separately for easy backup and export
- **No Database**: Simple flat file structure
- **External Change Detection**: Monitors for file changes outside the app

### Import/Export
- **Import Recipes**: Add recipes from `.cookbook.json` files
- **Import Cookbooks**: Import entire cookbooks with all recipes and categories
- **Export Recipes**: Share individual recipes as files
- **Export Cookbooks**: Share complete cookbooks with metadata
- **Smart Importing**: Automatic ID assignment and category mapping

## Project Structure

```
Cookbook/
├── Models/
│   ├── Cookbook.swift         # Cookbook metadata model
│   ├── Recipe.swift           # Recipe data model
│   ├── Category.swift         # Category with color support
│   └── CookbookExport.swift   # Export format structure
├── Services/
│   └── RecipeStore.swift      # Storage manager (iCloud/Local)
├── Views/
│   ├── CookbookSwitcherView.swift  # Multi-cookbook UI
│   ├── RecipeListView.swift        # Main recipe list with search
│   ├── RecipeDetailView.swift      # Recipe display & cooking workflow
│   ├── RecipeEditView.swift        # Recipe creation/editing
│   ├── CategoryPicker.swift        # Category management UI
│   ├── ICloudSetupView.swift       # Storage setup screen
│   ├── SettingsView.swift          # Cookbook settings & stats
│   └── ShareSheet.swift            # Platform-native sharing
├── CookbookApp.swift          # App entry point
└── Cookbook.entitlements      # iCloud configuration
```

## Setup Instructions

### 1. Xcode Project Setup

1. Open Xcode and create a new project:
   - Choose "Multiplatform App"
   - Product Name: "Cookbook"
   - Interface: SwiftUI
   - Language: Swift

2. Add all the Swift files to your project in the appropriate groups

3. Add the entitlements file to your project

### 2. Configure iCloud

1. In Xcode, select your project in the navigator
2. Select your app target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability" and add "iCloud"
5. Enable "iCloud Documents"
6. The container identifier should be: `iCloud.$(CFBundleIdentifier)`

### 3. Configure Entitlements

1. In your target's "Signing & Capabilities":
   - Make sure the entitlements file is linked
   - Verify iCloud is enabled with CloudDocuments service

### 4. Info.plist Configuration

Add these keys if needed:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>To add photos to your recipes</string>
```

### 5. Build and Run

1. Select your target device/simulator
2. Ensure you're signed in with an Apple ID that has iCloud enabled
3. Build and run (⌘R)

## Requirements

- iOS 17.0+ / iPadOS 17.0+ / macOS 14.0+
- Xcode 15.0+
- Apple ID with iCloud enabled (optional - can use local storage)
- Active internet connection for iCloud sync (if using iCloud)

## Usage

### First Launch

1. Choose your storage option:
   - **iCloud Drive**: Syncs across all your devices (recommended)
   - **Local Storage**: Device-only storage
2. If using iCloud, follow the on-screen setup instructions if needed
3. A default cookbook is created automatically

### Managing Cookbooks

1. Tap the cookbook name at the top to open the Cookbook Switcher
2. View all cookbooks with their recipe and category counts
3. Create a new cookbook with the "+" button
4. Switch cookbooks by tapping on one
5. Long-press (or right-click) a cookbook to:
   - Rename it
   - Delete it
   - Share it as a `.cookbook` file

### Adding a Recipe

1. Tap the "+" button in the navigation bar
2. Fill in the recipe details:
   - Add a photo (optional)
   - Enter title
   - Select or create a category (optional)
   - Set star rating (0-5 stars)
   - Set prep and cook times
   - Add source URL (optional)
   - Add ingredients (tap + to add each one)
   - Add directions (tap + to add each step)
   - Add any notes (optional)
3. Tap "Save"

### Viewing a Recipe

1. Tap any recipe from the list (or card in grid view)
2. View all recipe details, ratings, times, and cooking history
3. Check off ingredients as you gather them with satisfying animations
4. Follow the numbered directions
5. Tap "Mark as Cooked" when finished:
   - Scrolls to top
   - Animates ingredient checks
   - Clears checkboxes
   - Records the cooking date

### Editing a Recipe

1. Open the recipe detail view
2. Tap "Edit" in the navigation bar
3. Make your changes
4. Tap "Save"

### Managing Categories

1. When editing a recipe, tap the category picker
2. Create new categories with custom names and colors
3. Edit existing categories (name and color)
4. Delete categories (warns if assigned to recipes)
5. Categories are organized per-cookbook

### Searching Recipes

- Use the search bar at the top of the recipe list
- Search by recipe title or ingredient text
- Results filter in real-time as you type

### Switching Views (iPad/macOS)

- Toggle between grid and list view using the view picker
- Grid view shows recipe cards with images
- List view shows compact rows with thumbnails

### Importing and Exporting

**Import a Recipe:**
1. Receive a `.cookbook.json` file
2. Open it with the Cookbook app
3. Recipe is added to your current cookbook

**Export a Recipe:**
1. Open the recipe detail view
2. Tap the share button
3. Share the `.cookbook.json` file via any method

**Import a Cookbook:**
1. Receive a `.cookbook` file
2. Open it with the Cookbook app
3. New cookbook is created with all recipes and categories

**Export a Cookbook:**
1. Long-press a cookbook in the Cookbook Switcher
2. Select "Share"
3. Share the `.cookbook` file

## Data Storage Details

### File Structure

**iCloud Drive Path:**
```
iCloud Drive/Cookbo/Cookbooks/
├── my-cookbook-0eb471/            # <cookbook name>-<short id>
│   ├── cookbook.json              # Cookbook metadata
│   ├── categories.json            # Category definitions
│   ├── weekplan.json              # This Week review state
│   ├── Images/
│   │   └── [RecipeID].jpg
│   └── Recipes/
│       ├── banana-bread-3f2504.md     # <recipe title>-<short id>, Markdown
│       └── weeknight-pasta-0c9e77.md
└── family-recipes-5a391c/
    └── ...
```

**Local Storage Path:**
```
Documents/Cookbooks/
└── (same structure as above)
```

### Storage Options

**iCloud Drive (Default):**
- Automatic synchronization across all your devices
- Files visible in the Cookbo folder in iCloud Drive
- Changes propagate when devices are online
- External file changes are detected and reloaded
- Conflicts handled by last-write-wins

**Local Storage:**
- Device-only storage
- No internet connection required
- Faster file operations
- Manual backup required
- Option available during setup or in settings

### File Access

The Cookbook folder is made visible in iCloud Drive, allowing you to:
- Access recipe files directly from Finder/Files app
- Back up files manually
- Share files with other apps
- Edit JSON files externally (changes are detected)

### Data Format

All data is stored as JSON:
- **cookbook.json**: Cookbook metadata (ID, name, dates)
- **categories.json**: Array of categories with colors
- **[RecipeID].json**: Individual recipe data with ingredients, directions, etc.

## Customization

### Changing Colors
The app uses the system accent color by default. To customize:
1. Open `Assets.xcassets`
2. Add a new "Color Set" named "AccentColor"
3. Set your preferred color

### Modifying Time Increments
In `RecipeEditView.swift`, adjust the time picker increments:
```swift
ForEach(0..<60, id: \.self) { minute in
    if minute % 5 == 0 {  // Change this for different increments
        Text("\(minute)m").tag(minute)
    }
}
```

## Troubleshooting

### iCloud Not Available
1. The app will show the iCloud Setup screen if iCloud isn't detected
2. Follow the on-screen instructions for your platform
3. Alternatively, choose "Use Local Storage" to continue without iCloud
4. You can always enable iCloud later in settings

### iCloud Not Syncing
1. Verify iCloud Drive is enabled in System Settings
2. Check that you're signed in with an Apple ID
3. Ensure iCloud Drive has sufficient storage
4. Check internet connection
5. Force quit and restart the app
6. Check iCloud sync status in System Settings

### Recipes Not Appearing
1. Make sure you're viewing the correct cookbook
2. Check if search is active (clear search bar)
3. Force reload by switching cookbooks and back
4. Check that recipe files exist in the Cookbook folder

### Photos Not Showing
1. Grant photo library permissions when prompted
2. Check that image data is being properly encoded
3. Verify file sizes aren't too large (images stored as base64)
4. Try re-adding the photo

### Categories Not Working
1. Categories are per-cookbook - switch to the right cookbook
2. Check categories.json file in the cookbook folder
3. Deleted categories are automatically unassigned from recipes
4. Try recreating the category if it's corrupted

### Import/Export Issues
1. Ensure files have correct extensions (.cookbook.json or .cookbook)
2. Check that JSON files are valid
3. Verify file isn't corrupted
4. Check console logs for specific import errors

## Current Feature Highlights

- Multi-cookbook organization system
- Color-coded categories with visual grouping
- iPad-optimized grid and list views
- Full import/export for recipes and cookbooks
- No database, only flat files (iCloud sync or local)
- Search only your recipes

## Future Enhancements

Potential features to add:
- Import/Export as Markdown
- Drag-n-drop recipe ordering

## License

This project is provided as-is for personal use.

## Contributing

Feel free to fork and customize for your own needs!
