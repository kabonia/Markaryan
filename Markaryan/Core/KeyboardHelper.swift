import SwiftUI
import UIKit

/// The keyboard closes everywhere the same way:
///  • a «Готово» bar above every keyboard (number pads have no return key) — unless the screen already has its own bar,
///    or the field sends/searches with its return key (chats);
///  • a tap on an empty spot closes the keyboard (the tap still reaches buttons and other fields).
@MainActor
enum KeyboardHelper {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { note in
            guard let field = note.object as? UITextField else { return }
            MainActor.assumeIsolated {
                guard field.inputAccessoryView == nil, ![.send, .search, .go].contains(field.returnKeyType) else { return }
                field.inputAccessoryView = doneBar()
                field.reloadInputViews()
            }
        }
        NotificationCenter.default.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { note in
            guard let view = note.object as? UITextView, view.isEditable else { return }
            MainActor.assumeIsolated {
                guard view.inputAccessoryView == nil, ![.send, .search, .go].contains(view.returnKeyType) else { return }
                view.inputAccessoryView = doneBar()
                view.reloadInputViews()
            }
        }
    }

    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func doneBar() -> UIView {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let done = UIBarButtonItem(title: "Готово", style: .done, target: nil, action: nil)
        done.primaryAction = UIAction(title: "Готово") { _ in KeyboardHelper.dismiss() }
        done.tintColor = UIColor(Theme.orange)
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        bar.sizeToFit()
        return bar
    }
}

/// Put once at the root: adds «tap outside closes the keyboard» to the window (sheets live in the same window).
struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private weak var recognizer: UITapGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            guard let window, recognizer == nil, !(window.gestureRecognizers ?? []).contains(where: { $0.name == "keyboard.dismiss" }) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.name = "keyboard.dismiss"
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap
            KeyboardHelper.install()
        }

        @objc private func tapped() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // A tap into a text field (or its clear button) must not close the keyboard.
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
