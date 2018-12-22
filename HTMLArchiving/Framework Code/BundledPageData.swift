//
//  BundledPageData.swift
//  Tome
//
//  Created by Ben Gottlieb on 6/8/16.
//  Copyright © 2016 Stand Alone, Inc. All rights reserved.
//

import Foundation
import Plug

open class BundledPageData {
	public let html: String!
	public var title: String?
	let author: String?
	let desc: String?
	public let url: URL
	let keywords: String?
	
	let stylesheets: [String]
	let videos: [String]
	let scripts: [String]
	let links: [String]
	let frames: [String]
	let images: [String]
	
	public init?(propertyList dict: JSONDictionary) {
		title = dict["title"] as? String
		author = dict["author"] as? String
		desc = dict["description"] as? String
		keywords = dict["keywords"] as? String
		html = dict["html"] as? String
		
		stylesheets = dict["stylesheets"] as? [String] ?? []
		videos = dict["videoURLs"] as? [String] ?? []
		scripts = dict["scripts"] as? [String] ?? []
		links = dict["linkURLs"] as? [String] ?? []
		frames = dict["frameURLs"] as? [String] ?? []
		images = dict["imageURLs"] as? [String] ?? []
		
		if let urlString = dict["url"] as? String, let url = URL(string: urlString) , html != nil {
			self.url = url
		} else {
			self.url = URL.blank
			return nil
		}
	}
}
