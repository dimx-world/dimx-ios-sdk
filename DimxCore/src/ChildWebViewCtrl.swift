//
//  ChildWebViewCtrl.swift
//  DimxCore
//
//  Copyright © 2026 Dimensions. All rights reserved.
//

import UIKit
import WebKit

// Hosts a web view opened by window.open from the main one.
//
// The web view is created by WebViewCtrl from the configuration WebKit hands it, which is
// what keeps window.opener wired up; this controller only puts it on screen. The page
// normally closes itself - the Firebase auth handler does, once it has posted the
// credential back to its opener - so the close button is a way out of a popup that hangs
// rather than the expected path.
class ChildWebViewCtrl: UIViewController {
    let childWebView: WKWebView

    private var onClose: ((ChildWebViewCtrl) -> Void)?

    init(webView: WKWebView, onClose: @escaping (ChildWebViewCtrl) -> Void) {
        self.childWebView = webView
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        containerView.addSubview(closeButton)

        childWebView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(childWebView)

        let guide = containerView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),

            childWebView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            childWebView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            childWebView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            childWebView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
    }

    @objc private func closeTapped() {
        let onClose = self.onClose
        self.onClose = nil
        onClose?(self)
    }

    // Called for a swipe-down dismissal too, so the host stops tracking this controller
    // either way.
    func detach() {
        onClose = nil
    }
}
