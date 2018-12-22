//
//  HTMLArchive.swift
//  Tome
//
//  Created by Ben Gottlieb on 6/19/17.
//  Copyright © 2017 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CrossPlatformKit
import Gulliver

public struct HTMLArchive: Equatable {
	public var url: URL!
	public var originalURL: URL!
	public let data: Data?
	public var meta: [String: String]?
	public var thumbnailImage: UXImage?
	public var image: UXImage?
	public var text: String?
	public var title: String = NSLocalizedString("Untitled", comment: "Untitled")
	var plist: [String: Any]?
	public var isEmpty: Bool {
		guard let data = self.data else { return true }
		return data.count < 10
	}
	
	public static let mimeType = "application/x-webarchive"
	
	public init?(file: FilePath?) {
		self.init(data: file?.data ?? Data())
	}
	
	public init(url: URL, data: Data, meta: [String: String]? = nil, image: UXImage? = nil, text: String? = nil, title: String = NSLocalizedString("Untitled", comment: "Untitled"), thumbnailImage: UXImage? = nil) {
		self.url = url
		self.originalURL = url
		self.data = data
		self.meta = meta
		self.title = title
		self.image = image
		self.text = text
		self.thumbnailImage = thumbnailImage
	}

	public init?(data: Data) {
		if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
			self.plist = dict
			if let urlString = (dict?["WebMainResource"] as? [String: Any])?["WebResourceURL"] as? String {
				self.url = URL(string: urlString)
			} else {
				self.url = nil
			}
			self.data = data
		} else {
			self.data = data
			self.url = nil
		}
		
		self.originalURL = url
		if self.url == nil { return nil }
	}
	
	public func write(to url: URL) throws {
		try self.data?.write(to: url)
	}
	
	public static func ==(lhs: HTMLArchive, rhs: HTMLArchive) -> Bool {
		if let lhItem = lhs.url, let rhItem = rhs.url { return lhItem == rhItem }
		if let lhItem = lhs.data, let rhItem = rhs.data { return lhItem == rhItem }
		if let lhItem = lhs.originalURL, let rhItem = rhs.originalURL { return lhItem == rhItem }
		return false
	}
}
