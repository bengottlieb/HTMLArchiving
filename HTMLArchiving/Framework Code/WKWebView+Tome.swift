//
//  WKWebView+Tome.swift
//  Tome
//
//  Created by Ben Gottlieb on 1/3/17.
//  Copyright © 2017 Stand Alone, Inc. All rights reserved.
//

import WebKit

extension WKWebView {
	func fetchHTML(_ completion: @escaping (String?) -> Void) {
		self.evaluateJavaScript("document.documentElement.outerHTML.toString()") { html, error in
			completion(html as? String)
		}
	}
	
    #if os(iOS)
		func setVisiblePercentages(start: Double?, end: Double?) {
			let scrollHeight = self.scrollView.contentSize.height
			let top = self.scrollView.contentOffset.y
			let isFullPage = (self.bounds.height >= self.scrollView.contentSize.height)
	
			if isFullPage { return }
	
			let current = Double(Double(top / scrollHeight))
			if let val = start, current != val {
				let newOffset = CGFloat(val) * scrollHeight
				self.scrollView.setContentOffset(CGPoint(x: 0, y: newOffset), animated: false)
			}
		}
	
		func fetchVisiblePercentages(completion: @escaping (Double?, Double?) -> Void) {
			let scrollHeight = self.scrollView.contentSize.height
			let start = self.scrollView.contentOffset.y
			let isFullPage = (self.bounds.height >= self.scrollView.contentSize.height)
			let end = start + self.bounds.height
			DispatchQueue.main.async {
				completion(isFullPage ? 0.0 : Double(start / scrollHeight), isFullPage ? 1.0 : Double(end / scrollHeight))
			}
		}
	#else
		func setVisiblePercentages(start: Double?, end: Double?) {
			guard let start = start else { return }
			let script = """
				var body = document.body, html = document.documentElement;
				var height = Math.max( body.scrollHeight, body.offsetHeight, html.clientHeight, html.scrollHeight, html.offsetHeight );
				var scrollPosition = window.scrollY;
				var newPosition = \(start) * (height - window.innerHeight);
				window.scrollTo(0, newPosition)
				"""
			
			self.evaluateJavaScript(script) { result, error in
				
			}
		}
		func fetchVisiblePercentages(completion: @escaping (Double?, Double?) -> Void) {
			let script = """
				var body = document.body, html = document.documentElement;
				var height = Math.max( body.scrollHeight, body.offsetHeight, html.clientHeight, html.scrollHeight, html.offsetHeight );
				var scrollPosition = window.scrollY;
				var availableHeight = (height - window.innerHeight);
				var start = scrollPosition / availableHeight;
				var end = start + window.innerHeight / availableHeight;
				[start, end];
			"""
			
			self.evaluateJavaScript(script) { result, error in
				if let values = result as? [Double], values.count > 1 {
					completion(values[0], values[1])
				} else {
					completion(nil, nil)
				}
			}
		}
    #endif
}
