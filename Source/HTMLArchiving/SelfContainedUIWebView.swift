//
//  SelfContainedUIWebView.swift
//  Internal-iOS
//
//  Created by Ben Gottlieb on 7/23/17.
//  Copyright © 2017 Stand Alone, Inc. All rights reserved.
//


import UIKit

open class SelfContainedUIWebView: UIWebView {
	
	var completions: [WebLoadCompletionBlock] = []
	//var url: URL? { return self.url }
	
	open func load(url: URL, withCompletion completion: WebLoadCompletionBlock? = nil) {
		let request = URLRequest(url: url)
		return self.load(request: request, withCompletion: completion)
	}
	
	open func load(request: URLRequest, withCompletion completion: WebLoadCompletionBlock? = nil) {
		self.delegate = self
		if let completion = completion { self.completions.append(completion) }
		
		self.loadRequest(request)
	}
	
	open func loadHTMLString(string: String, baseURL: URL?, completion: WebLoadCompletionBlock? = nil) {
		self.delegate = self
		if let completion = completion { self.completions.append(completion) }
		self.loadHTMLString(string, baseURL: baseURL)
	}
	
	func callCompletions(result: Bool) {
		let comps = self.completions
		self.completions = []
		DispatchQueue.main.async {
			comps.forEach { $0(result) }
		}
	}
	
	//	public override var snapshotImage: NSImage? {
	//		guard let view = self.mainFrame.frameView.documentView else { return nil }
	//		let data = view.dataWithPDF(inside: view.bounds)
	//		return NSImage(data: data)
	//	}
	
	public func extractTitle(completion: @escaping (String?) -> Void) {
		let string = self.stringByEvaluatingJavaScript(from: "document.title")
		completion(string)
	}
	
}

extension SelfContainedUIWebView: UIWebViewDelegate {
	public func webViewDidFinishLoad(_ webView: UIWebView) {
		self.callCompletions(result: true)
	}
	
	public func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
		self.callCompletions(result: false)
	}
}


