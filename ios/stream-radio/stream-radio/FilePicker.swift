import SwiftUI
import UniformTypeIdentifiers

// MARK: - 跨平台 List 样式兼容
extension ListStyle where Self == InsetListStyle {
    /// 兼容 iOS 的 insetGrouped / macOS 的 inset
    static var platformGrouped: InsetListStyle { .inset }
}

#if os(iOS)
extension ListStyle where Self == InsetGroupedListStyle {
    static var platformGrouped: InsetGroupedListStyle { .insetGrouped }
}
#endif

#if os(iOS)
import UIKit

/// iOS 文件选择器（UIDocumentPicker 封装）
struct FilePickerView: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FilePickerView
        init(_ parent: FilePickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPick(nil)
        }
    }
}

#elseif os(macOS)
import AppKit

/// macOS 文件选择器（NSOpenPanel 封装）
///
/// 用 NSViewControllerRepresentable 只是为了和 iOS 端调用签名一致；
/// 实际打开操作在 makeNSViewController 里直接弹 NSOpenPanel。
struct FilePickerView: NSViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeNSViewController(context: Context) -> NSViewController {
        let vc = NSViewController()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.item]
            panel.canDownloadUbiquitousContents = true
            panel.canResolveUbiquitousConflicts = true
            if panel.runModal() == .OK {
                onPick(panel.url)
            } else {
                onPick(nil)
            }
        }
        return vc
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject {}
}
#endif
