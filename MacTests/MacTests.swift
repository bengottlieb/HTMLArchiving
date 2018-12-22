//
//  MacTests.swift
//  MacTests
//
//  Created by Ben Gottlieb on 12/22/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import XCTest
import HTMLArchiving

class ArchiveTests: XCTestCase {
	var html: String!
	
	override func setUp() {
		super.setUp()
		let url = Bundle(for: type(of: self)).url(forResource: "parsertest", withExtension: "html")!
		self.html = try! String(contentsOf: url)
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}
	
	func testArchiving() {
		let archiver = HTMLArchiver(url: URL(string: "http://www.newyorker.com/")!, html: self.html)
		let expectation = self.expectation(description: "Parse HTML")
		archiver!.archive { results, error in
			if let data = results?.data {
				print("Finished archiving with \(data.count) bytes")
			} else if let error = error {
				XCTAssertTrue(false, "Failed to archive: \(error)")
			}
			expectation.fulfill()
		}
		waitForExpectations(timeout: 500) { error in }
	}
	
	func testPerformanceExample() {
		// This is an example of a performance test case.
		self.measure {
			// Put the code you want to measure the time of here.
		}
	}
	
}
