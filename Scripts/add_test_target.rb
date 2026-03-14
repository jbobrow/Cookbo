#!/usr/bin/env ruby
# Adds a CookbookTests unit test target to the Xcode project.
# Run once from the repo root: ruby Scripts/add_test_target.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Cookbook.xcodeproj', __dir__)
TESTS_DIR    = File.expand_path('../CookbookTests', __dir__)

proj = Xcodeproj::Project.open(PROJECT_PATH)

# Bail out if the target already exists
if proj.targets.any? { |t| t.name == 'CookbookTests' }
  puts "CookbookTests target already exists — nothing to do."
  exit 0
end

app_target = proj.targets.find { |t| t.name == 'Cookbook' }
raise "Could not find Cookbook target" unless app_target

# ── Create test target ───────────────────────────────────────────────────────
test_target = proj.new_target(
  :unit_test_bundle,
  'CookbookTests',
  :ios,
  '17.6'
)

# ── Build settings ───────────────────────────────────────────────────────────
test_target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION']                      = '5.0'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']          = 'com.jonbobrow.CookbookTests'
  config.build_settings['TEST_HOST']                          = '$(BUILT_PRODUCTS_DIR)/Cookbook.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Cookbook'
  config.build_settings['BUNDLE_LOADER']                      = '$(TEST_HOST)'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS']            = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']         = '17.6'
  config.build_settings['CODE_SIGN_STYLE']                    = 'Automatic'
  config.build_settings['GENERATE_INFOPLIST_FILE']            = 'YES'
end

# ── Add dependency on the app target ────────────────────────────────────────
test_target.add_dependency(app_target)

# ── Create CookbookTests group in the project navigator ─────────────────────
tests_group = proj.main_group.new_group('CookbookTests', 'CookbookTests')

# ── Add InstagramParserTests.swift ───────────────────────────────────────────
test_file = tests_group.new_file('InstagramParserTests.swift')
test_target.source_build_phase.add_file_reference(test_file)

# ── Add RecipeParserCore.swift so the test target can compile it directly ────
# (same pattern used by the Cookbook and ShareExtension targets)
shared_group = proj.main_group.groups.find { |g| g.path == 'Shared' }
if shared_group
  core_ref = shared_group.files.find { |f| f.path == 'RecipeParserCore.swift' }
  if core_ref
    test_target.source_build_phase.add_file_reference(core_ref)
    puts "Added RecipeParserCore.swift to CookbookTests source build phase."
  else
    warn "WARNING: RecipeParserCore.swift not found in Shared group"
  end
else
  warn "WARNING: Shared group not found in project navigator"
end

proj.save
puts "Done — CookbookTests target added to #{PROJECT_PATH}"
