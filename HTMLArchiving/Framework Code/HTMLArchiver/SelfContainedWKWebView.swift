//
//  SelfContainedWKWebView.swift
//  Tome
//
//  Created by Ben Gottlieb on 12/31/16.
//  Copyright © 2016 Stand Alone, Inc. All rights reserved.
//

import Foundation
import WebKit
import Gulliver

public protocol SelfContainedWebViewDelegate: WKNavigationDelegate {
	func webView(_ webView: WKWebView, didRedirectFrom: URL, to: URL)
	func webView(_ webView: WKWebView, shouldAllowNavigationTo request: URLRequest) -> Bool
	func webView(_ webView: WKWebView, shouldCompleteNavigationTo response: WKNavigationResponse) -> Bool
}

extension SelfContainedWebViewDelegate {
	func webView(_ webView: WKWebView, shouldAllowNavigationTo request: URLRequest) -> Bool { return true }
}

public typealias WebLoadCompletionBlock = (Bool) -> Void

@objc open class SelfContainedWKWebView: WKWebView {
	var pendingScrollPercentage: CGFloat?
	var originalURL: URL?
	
	public convenience init(defaultFrame: CGRect) {
		let prefs = WKPreferences()
		let config = WKWebViewConfiguration()
		
		config.preferences = prefs
		
		self.init(frame: defaultFrame, configuration: config)
	}
	
	public override init(frame: CGRect, configuration: WKWebViewConfiguration) {
		super.init(frame: frame, configuration: configuration)
		self.navigationDelegate = self
		self.uiDelegate = self
	}
	
	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		self.navigationDelegate = self
		self.uiDelegate = self
	}
	
	open override var navigationDelegate: WKNavigationDelegate? { didSet { if self.navigationDelegate !== self { self.addNavigationDelegate(self.navigationDelegate); self.navigationDelegate = self } }}
	open override var uiDelegate: WKUIDelegate? { didSet { if self.uiDelegate !== self { self.addUIDelegate(self.uiDelegate); self.uiDelegate = self } }}
	var completions: [WebLoadCompletionBlock] = []
	var redirectionOrigin: URL?
	var isRedirecting: Bool { return self.redirectionOrigin != nil }
	
	var uiDelegates: WeakArray<WKUIDelegate> = []
	var navigationDelegates: WeakArray<WKNavigationDelegate> = []
	func addUIDelegate(_ delegate: WKUIDelegate?) {
		if delegate == nil { self.uiDelegates = [] }
		if let delegate = delegate, !self.uiDelegates.contains(where: { $0 === delegate }) { self.uiDelegates.append(delegate) }
	}
	
	func addNavigationDelegate(_ delegate: WKNavigationDelegate?) {
		if delegate == nil { self.navigationDelegates = [] }
		if let delegate = delegate, !self.navigationDelegates.contains(where: { $0 === delegate }) { self.navigationDelegates.append(delegate) }
	}

	public func extractTitle(completion: @escaping (String?) -> Void) {
		self.evaluateJavaScript("document.title") { result, error in
			completion(result as? String)
		}
	}
	
	public func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL, completion: WebLoadCompletionBlock? = nil) -> WKNavigation? {
		if let completion = completion { self.completions.append(completion) }
		self.redirectionOrigin = nil
		return super.loadFileURL(URL, allowingReadAccessTo: readAccessURL)
	}
	
	@discardableResult open func load(url: URL, scrollPercentage: CGFloat? = nil, withCompletion completion: WebLoadCompletionBlock? = nil) -> WKNavigation? {
		let request = URLRequest(url: url)
		self.originalURL = url
		self.redirectionOrigin = nil
		return self.load(request: request, scrollPercentage: scrollPercentage, withCompletion: completion)
	}
	
	@discardableResult open func load(request: URLRequest, scrollPercentage: CGFloat? = nil, withCompletion completion: WebLoadCompletionBlock? = nil) -> WKNavigation? {
		if let completion = completion { self.completions.append(completion) }
		self.originalURL = request.url
		self.pendingScrollPercentage = scrollPercentage
		self.redirectionOrigin = nil
		return super.load(request)
	}
	
	@discardableResult open func load(data: Data, mimeType MIMEType: String, characterEncodingName: String, baseURL: URL, completion: WebLoadCompletionBlock?) -> WKNavigation? {
		self.redirectionOrigin = nil
		if let completion = completion { self.completions.append(completion) }
		return super.load(data, mimeType: MIMEType, characterEncodingName: characterEncodingName, baseURL: baseURL)
	}

	open func load(archive: HTMLArchive, scrollPercentage: CGFloat? = nil, withCompletion completion: WebLoadCompletionBlock? = nil) {
		self.redirectionOrigin = nil
		if let completion = completion { self.completions.append(completion) }
		self.pendingScrollPercentage = scrollPercentage

		if let data = archive.data {
			self.load(data: data, mimeType: HTMLArchive.mimeType, characterEncodingName: "", baseURL: archive.url, completion: completion)
		}
	}
	
	@discardableResult open func loadHTMLString(string: String, baseURL: URL?, scrollPercentage: CGFloat?, completion: WebLoadCompletionBlock? = nil) -> WKNavigation? {
		if let completion = completion { self.completions.append(completion) }
		self.redirectionOrigin = nil
		self.navigationDelegate = self
		self.pendingScrollPercentage = scrollPercentage
		return self.loadHTMLString(string, baseURL: baseURL)
	}
	
	func callCompletions(result: Bool) {
		let comps = self.completions
		self.completions = []
		DispatchQueue.main.async {
			comps.forEach { $0(result) }
		}
	}
}

extension SelfContainedWKWebView: WKUIDelegate {
	public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		if navigationAction.targetFrame?.isMainFrame != true {
			
			self.load(request: navigationAction.request)
		}
		
		
		return nil;
	}
	
	public func webViewDidClose(_ webView: WKWebView) {
		self.uiDelegates.forEach { $0.webViewDidClose?(webView) }
	}
	public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedBy frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
		self.uiDelegates.forEach { $0.webView?(webView, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler) }
	}

	public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
		self.uiDelegates.forEach { $0.webView?(webView, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler) }
	}

	public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
		self.uiDelegates.forEach { $0.webView?(webView, runJavaScriptTextInputPanelWithPrompt: prompt, defaultText: defaultText, initiatedByFrame: frame, completionHandler: completionHandler) }
	}

	#if os(iOS)
		public func webView(_ webView: WKWebView, shouldPreviewElement elementInfo: WKPreviewElementInfo) -> Bool {
			return self.uiDelegates.reduce(false) { $0 || ($1.webView?(webView, shouldPreviewElement: elementInfo) ?? false) }
		}

		public func webView(_ webView: WKWebView, previewingViewControllerForElement elementInfo: WKPreviewElementInfo, defaultActions previewActions: [WKPreviewActionItem]) -> UIViewController? {
			for delegate in self.uiDelegates {
				if let controller = delegate.webView?(webView, previewingViewControllerForElement: elementInfo, defaultActions: previewActions) { return controller }
			}
			return nil
		}

		public func webView(_ webView: WKWebView, commitPreviewingViewController previewingViewController: UIViewController) {
			self.uiDelegates.forEach { $0.webView?(webView, commitPreviewingViewController: previewingViewController) }
		}
	#endif


}

extension SelfContainedWKWebView: WKNavigationDelegate {
	public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		if let scroll = self.pendingScrollPercentage {
			self.setVisiblePercentages(start: Double(scroll), end: nil)
		}

		if self.redirectionOrigin == nil {			//only call this if we're not redirecting
			self.callCompletions(result: true)
		}
		self.navigationDelegates.forEach { $0.webView?(webView, didFinish: navigation!) }
	}
	
	public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		self.callCompletions(result: false)
		self.navigationDelegates.forEach { $0.webView?(webView, didFailProvisionalNavigation: navigation, withError: error) }
	}
	
	public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		self.callCompletions(result: false)
		self.navigationDelegates.forEach { $0.webView?(webView, didFail: navigation, withError: error) }
	}
	
	open func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		if navigationAction.navigationType.rawValue != -1 {
			self.redirectionOrigin = nil
		}
		
		for delegate in self.navigationDelegates {
			if navigationAction.navigationType != .other, (navigationAction.targetFrame?.isMainFrame == true || navigationAction.targetFrame == nil), let wkDelegate = delegate as? SelfContainedWebViewDelegate, !wkDelegate.webView(self, shouldAllowNavigationTo: navigationAction.request) {
				decisionHandler(.cancel)
				return
			}
		}

		for delegate in self.navigationDelegates {
			if delegate.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler) != nil {
				return
			}
		}
		decisionHandler(.allow)
	}

	open func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
		for delegate in self.navigationDelegates {
			if let wkDelegate = delegate as? SelfContainedWebViewDelegate, !wkDelegate.webView(self, shouldCompleteNavigationTo: navigationResponse) {
				decisionHandler(.cancel)
				return
			}

			if delegate.webView?(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler) != nil {
				return
			}
		}
		decisionHandler(.allow)
	}
	
	
	open func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		self.navigationDelegates.forEach { $0.webView?(webView, didStartProvisionalNavigation: navigation!) }
	}
	
	
	open func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
		self.redirectionOrigin = self.originalURL
		self.navigationDelegates.forEach { $0.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation!) }
	}
	
	
	open func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		self.navigationDelegates.forEach { $0.webView?(webView, didCommit: navigation!) }
		if let origin = self.redirectionOrigin, let dest = webView.url {
			self.redirectionOrigin = nil
			self.navigationDelegates.forEach { if let delegate = $0 as? SelfContainedWebViewDelegate {
				delegate.webView(self, didRedirectFrom: origin, to: dest)
			}}
		}
	}
	
	open func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		for delegate in self.navigationDelegates {
			if delegate.webView?(webView, didReceive: challenge, completionHandler: completionHandler) != nil {
				return
			}
		}
		completionHandler(.useCredential, challenge.proposedCredential)
	}
	
	
	open func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		self.navigationDelegates.forEach { $0.webViewWebContentProcessDidTerminate?(webView) }
	}
	
	

}

