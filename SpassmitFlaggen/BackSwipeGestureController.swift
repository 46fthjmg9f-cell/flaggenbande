import SwiftUI
import UIKit

struct BackSwipeGestureController: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> HostingProbeViewController {
        let viewController = HostingProbeViewController()
        viewController.onNavigationEnvironmentChanged = { [weak viewController] in
            guard let viewController else { return }
            context.coordinator.refresh(from: viewController)
        }
        context.coordinator.setDisabled(isDisabled, from: viewController)
        return viewController
    }

    func updateUIViewController(_ uiViewController: HostingProbeViewController, context: Context) {
        context.coordinator.setDisabled(isDisabled, from: uiViewController)
    }

    static func dismantleUIViewController(_ uiViewController: HostingProbeViewController, coordinator: Coordinator) {
        coordinator.restoreBackSwipe()
    }

    final class HostingProbeViewController: UIViewController {
        var onNavigationEnvironmentChanged: (() -> Void)?

        override func loadView() {
            view = ProbeView()
            (view as? ProbeView)?.onWindowChanged = { [weak self] in
                self?.onNavigationEnvironmentChanged?()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onNavigationEnvironmentChanged?()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onNavigationEnvironmentChanged?()
        }
    }

    final class ProbeView: UIView {
        var onWindowChanged: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChanged?()
        }
    }

    final class Coordinator {
        private var controlledGestures: [ObjectIdentifier: GestureState] = [:]
        private let blockingDelegate = BlockingGestureDelegate()
        private var isDisabled: Bool = false
        private var deferredApplyWorkItem: DispatchWorkItem?

        deinit {
            restoreBackSwipe()
        }

        func setDisabled(_ isDisabled: Bool, from viewController: UIViewController) {
            self.isDisabled = isDisabled
            applyBackSwipeState(from: viewController, schedulesEnforcement: true)
        }

        func refresh(from viewController: UIViewController) {
            applyBackSwipeState(from: viewController, schedulesEnforcement: true)
        }

        func restoreBackSwipe() {
            deferredApplyWorkItem?.cancel()
            deferredApplyWorkItem = nil

            for state in controlledGestures.values {
                guard let gestureRecognizer = state.gestureRecognizer else { continue }
                if gestureRecognizer.delegate === blockingDelegate {
                    gestureRecognizer.delegate = state.originalDelegate
                }
                gestureRecognizer.isEnabled = true
            }

            controlledGestures.removeAll()
            blockingDelegate.isBlocking = false
        }

        private func applyBackSwipeState(from viewController: UIViewController, schedulesEnforcement: Bool) {
            let navigationControllers = findNavigationControllers(from: viewController)

            guard !navigationControllers.isEmpty else {
                if schedulesEnforcement {
                    scheduleDeferredApply(from: viewController)
                }
                return
            }

            let activeGestureIDs = Set(navigationControllers.compactMap { navigationController -> ObjectIdentifier? in
                guard let gestureRecognizer = navigationController.interactivePopGestureRecognizer else { return nil }
                return ObjectIdentifier(gestureRecognizer)
            })

            let staleGestureIDs = controlledGestures.keys.filter { !activeGestureIDs.contains($0) }
            for gestureID in staleGestureIDs {
                guard let state = controlledGestures[gestureID] else { continue }
                if let gestureRecognizer = state.gestureRecognizer {
                    if gestureRecognizer.delegate === blockingDelegate {
                        gestureRecognizer.delegate = state.originalDelegate
                    }
                    gestureRecognizer.isEnabled = true
                }
                controlledGestures.removeValue(forKey: gestureID)
            }

            for navigationController in navigationControllers {
                guard let gestureRecognizer = navigationController.interactivePopGestureRecognizer else { continue }
                let gestureID = ObjectIdentifier(gestureRecognizer)

                if isDisabled {
                    if controlledGestures[gestureID] == nil {
                        controlledGestures[gestureID] = GestureState(
                            gestureRecognizer: gestureRecognizer,
                            originalDelegate: gestureRecognizer.delegate
                        )
                    }
                    blockingDelegate.isBlocking = true
                    if gestureRecognizer.delegate !== blockingDelegate {
                        gestureRecognizer.delegate = blockingDelegate
                    }
                } else {
                    if let state = controlledGestures[gestureID] {
                        if gestureRecognizer.delegate === blockingDelegate {
                            gestureRecognizer.delegate = state.originalDelegate
                        }
                        if !gestureRecognizer.isEnabled {
                            gestureRecognizer.isEnabled = true
                        }
                        controlledGestures.removeValue(forKey: gestureID)
                    }
                }
            }

            if !isDisabled {
                deferredApplyWorkItem?.cancel()
                deferredApplyWorkItem = nil
                blockingDelegate.isBlocking = false
            }
        }

        private func scheduleDeferredApply(from viewController: UIViewController) {
            guard isDisabled else { return }
            deferredApplyWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak viewController] in
                guard let self, let viewController, self.isDisabled else { return }
                self.deferredApplyWorkItem = nil
                self.applyBackSwipeState(from: viewController, schedulesEnforcement: false)
            }
            deferredApplyWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func findNavigationControllers(from viewController: UIViewController) -> [UINavigationController] {
            var navigationControllers: [UINavigationController] = []
            var seenIDs: Set<ObjectIdentifier> = []

            func append(_ navigationController: UINavigationController?) {
                guard let navigationController else { return }
                let id = ObjectIdentifier(navigationController)
                guard !seenIDs.contains(id) else { return }
                seenIDs.insert(id)
                navigationControllers.append(navigationController)
            }

            append(viewController.navigationController)

            var parent = viewController.parent
            while let currentParent = parent {
                append(currentParent as? UINavigationController)
                append(currentParent.navigationController)
                parent = currentParent.parent
            }

            append(findNavigationController(inResponderChainFrom: viewController.view))

            if let rootViewController = viewController.view.window?.rootViewController {
                collectNavigationControllers(in: rootViewController, into: &navigationControllers, seenIDs: &seenIDs)
            }

            for rootViewController in activeWindowRootViewControllers() {
                collectNavigationControllers(in: rootViewController, into: &navigationControllers, seenIDs: &seenIDs)
            }

            return navigationControllers
        }

        private func activeWindowRootViewControllers() -> [UIViewController] {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter { !$0.isHidden && $0.windowLevel == .normal }
                .compactMap(\.rootViewController)
        }

        private func findNavigationController(inResponderChainFrom view: UIView?) -> UINavigationController? {
            var responder: UIResponder? = view
            while let currentResponder = responder {
                if let navigationController = currentResponder as? UINavigationController {
                    return navigationController
                }
                if let viewController = currentResponder as? UIViewController,
                   let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = currentResponder.next
            }
            return nil
        }

        private func collectNavigationControllers(
            in viewController: UIViewController,
            into navigationControllers: inout [UINavigationController],
            seenIDs: inout Set<ObjectIdentifier>
        ) {
            if let navigationController = viewController as? UINavigationController {
                let id = ObjectIdentifier(navigationController)
                if !seenIDs.contains(id) {
                    seenIDs.insert(id)
                    navigationControllers.append(navigationController)
                }
            }

            if let navigationController = viewController.navigationController {
                let id = ObjectIdentifier(navigationController)
                if !seenIDs.contains(id) {
                    seenIDs.insert(id)
                    navigationControllers.append(navigationController)
                }
            }

            for child in viewController.children {
                collectNavigationControllers(in: child, into: &navigationControllers, seenIDs: &seenIDs)
            }

            if let presented = viewController.presentedViewController {
                collectNavigationControllers(in: presented, into: &navigationControllers, seenIDs: &seenIDs)
            }
        }
    }

    final class GestureState {
        weak var gestureRecognizer: UIGestureRecognizer?
        weak var originalDelegate: UIGestureRecognizerDelegate?

        init(gestureRecognizer: UIGestureRecognizer, originalDelegate: UIGestureRecognizerDelegate?) {
            self.gestureRecognizer = gestureRecognizer
            self.originalDelegate = originalDelegate
        }
    }

    final class BlockingGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        var isBlocking: Bool = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !isBlocking
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}
