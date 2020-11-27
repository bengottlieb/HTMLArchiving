//
//  String+Extensions.swift
//  HTMLArchiving_iOS
//
//  Created by Ben Gottlieb on 12/21/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Foundation

extension String {
	var urlFragment: String? {
		if self.hasPrefix("url("), self.hasSuffix(")") {
			let first = self.index(4)
			let last = self.index(self.count - 1)
			
			let frag = self[first..<last]
			return String(frag)
		}
		return nil
	}
}
