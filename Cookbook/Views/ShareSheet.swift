import SwiftUI

/// What sharing a recipe sends: its source link, so it can be texted and opens
/// anywhere. A recipe with no link (one typed in by hand) goes as its Markdown file.
enum RecipeShareItems {
    static func items(for recipe: Recipe) -> [Any]? {
        if let url = URL(string: recipe.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return [url]
        }

        let fileName = "\(recipe.title.replacingOccurrences(of: " ", with: "_")).md"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try RecipeMarkdownSerializer.serialize(recipe).write(to: fileURL, atomically: true, encoding: .utf8)
            return [fileURL]
        } catch {
            #if DEBUG
            print("Error sharing recipe: \(error)")
            #endif
            return nil
        }
    }
}

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#elseif os(macOS)
import AppKit

struct ShareSheet: NSViewRepresentable {
    let items: [Any]
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            guard let url = items.first as? URL else { return }
            
            let picker = NSSharingServicePicker(items: [url])
            picker.show(
                relativeTo: .zero,
                of: view,
                preferredEdge: .minY
            )
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
