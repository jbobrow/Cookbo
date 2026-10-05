import Foundation

/// The web page a share carries, however the sharing app packed it. Safari
/// hands over a URL, but SwiftUI's ShareLink and others send data, which can
/// be an archived URL rather than the address's text.
enum SharedURL {
    static func load(from provider: NSItemProvider, completion: @escaping @Sendable (String?) -> Void) {
        guard provider.canLoadObject(ofClass: URL.self) else {
            loadItem(from: provider, completion: completion)
            return
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, isWeb(url) {
                completion(url.absoluteString)
            } else {
                loadItem(from: provider, completion: completion)
            }
        }
    }

    private static func loadItem(from provider: NSItemProvider, completion: @escaping @Sendable (String?) -> Void) {
        provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
            completion(webAddress(in: item))
        }
    }

    static func webAddress(in item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return isWeb(url) ? url.absoluteString : nil
        }
        if let text = item as? String {
            return webAddress(inText: text)
        }
        guard let data = item as? Data else { return nil }
        if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as URL?, isWeb(url) {
            return url.absoluteString
        }
        if let text = String(data: data, encoding: .utf8), let address = webAddress(inText: text) {
            return address
        }
        if let url = URL(dataRepresentation: data, relativeTo: nil), isWeb(url) {
            return url.absoluteString
        }
        return nil
    }

    private static func webAddress(inText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isWeb(url) else { return nil }
        return trimmed
    }

    private static func isWeb(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

#if canImport(UIKit)
import UIKit
import SwiftUI

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.jonbobrow.Cookbook"
    private let pendingRecipesFolder = "PendingRecipes"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractURL()
    }

    private func extractURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            dismiss()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    SharedURL.load(from: provider) { [weak self] urlString in
                        DispatchQueue.main.async {
                            if let urlString {
                                self?.showShareUI(urlString: urlString)
                            } else {
                                self?.dismiss()
                            }
                        }
                    }
                    return
                }

                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            if let text = data as? String,
                               let url = URL(string: text),
                               url.scheme == "http" || url.scheme == "https" {
                                self?.showShareUI(urlString: text)
                            } else {
                                self?.dismiss()
                            }
                        }
                    }
                    return
                }
            }
        }

        dismiss()
    }

    private func showShareUI(urlString: String) {
        let shareView = ShareExtensionView(
            urlString: urlString,
            onSave: { [weak self] recipe in
                self?.saveRecipe(recipe)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func saveRecipe(_ recipe: RecipeParser.ParsedRecipe) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let folder = containerURL.appendingPathComponent(pendingRecipesFolder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).json"
        let fileURL = folder.appendingPathComponent(fileName)

        if let data = try? JSONEncoder().encode(recipe) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

#elseif canImport(AppKit)
import AppKit
import SwiftUI

class ShareViewController: NSViewController {

    private let appGroupID = "group.com.jonbobrow.Cookbook"
    private let pendingRecipesFolder = "PendingRecipes"

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        extractURL()
    }

    private func extractURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            dismiss()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    SharedURL.load(from: provider) { [weak self] urlString in
                        DispatchQueue.main.async {
                            if let urlString {
                                self?.showShareUI(urlString: urlString)
                            } else {
                                self?.dismiss()
                            }
                        }
                    }
                    return
                }

                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            if let text = data as? String,
                               let url = URL(string: text),
                               url.scheme == "http" || url.scheme == "https" {
                                self?.showShareUI(urlString: text)
                            } else {
                                self?.dismiss()
                            }
                        }
                    }
                    return
                }
            }
        }

        dismiss()
    }

    private func showShareUI(urlString: String) {
        let shareView = ShareExtensionView(
            urlString: urlString,
            onSave: { [weak self] recipe in
                self?.saveRecipe(recipe)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: shareView)
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.width, .height]
        view.addSubview(hostingView)
    }

    private func saveRecipe(_ recipe: RecipeParser.ParsedRecipe) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let folder = containerURL.appendingPathComponent(pendingRecipesFolder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).json"
        let fileURL = folder.appendingPathComponent(fileName)

        if let data = try? JSONEncoder().encode(recipe) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
#endif
