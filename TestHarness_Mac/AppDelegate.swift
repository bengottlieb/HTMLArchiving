//
//  AppDelegate.swift
//  TestHarness_Mac
//
//  Created by Ben Gottlieb on 12/21/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Cocoa
import HTMLArchiving
import WebKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	@IBOutlet weak var window: NSWindow!
	var webview: WKWebView!

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		HTMLArchiver(url: URL(string: "https://cnn.com")!)?.archive() { archive, error in
			print("Done")
		}

		self.showWindow()
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
	}

	func showWindow() {
		self.window.makeKeyAndOrderFront(nil)

		guard let view = window.contentView else { return }
		self.webview = WKWebView(frame: view.bounds, configuration: WKWebViewConfiguration())

		view.addSubview(self.webview)
		self.webview.autoresizingMask = [.width, .height]

//		let url = Bundle.main.url(forResource: "samplepage", withExtension: "webarchive")!

		let url = URL(string: "https://github.com/")!
		self.webview.load(URLRequest(url: url))

	}

	@IBAction func save(_ sender: Any?) {
		let archiver = HTMLArchiver(webView: self.webview)
		archiver?.archive() { archive, error in
			guard let data = archive?.data else { return }

			let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").appendingPathComponent("archive.webarchive")
			try! data.write(to: file)
		}
	}

}

