//
//  AppDelegate.swift
//  TestHarness_Mac
//
//  Created by Ben Gottlieb on 12/21/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Cocoa
import HTMLArchiving

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	@IBOutlet weak var window: NSWindow!


	func applicationDidFinishLaunching(_ aNotification: Notification) {
		HTMLArchiver(url: URL(string: "https://cnn.com")!)?.archive() { archive, error in
			print("Done")
		}
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
	}


}

