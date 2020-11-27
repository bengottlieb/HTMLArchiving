//
//  WebViewArchivedResource.swift
//  Archivist
//
//  Created by Ben Gottlieb on 1/10/16.
//  Copyright © 2016 Stand Alone, Inc. All rights reserved.
//

import WebKit
import Plug

infix operator ≈≈ : ComparisonPrecedence

extension HTMLArchiver {
	public static var forceHTTPS = false
	enum ResourceType { case unknown, images, links, frames, styleSheets, videos, scripts, embed, thumbnailImage
		var next: ResourceType? {
			if let index = ResourceType.resourceOrder.firstIndex(of: self) , index < (ResourceType.resourceOrder.count - 1) { return ResourceType.resourceOrder[index + 1] }
			return nil
		}
		
		var description: String {
			switch self {
			case .unknown: return "Unknown"
			case .images: return "Images"
			case .links: return "Links"
			case .frames: return "Frames"
			case .styleSheets: return "StyleSheets"
			case .embed: return "Embed"
			case .videos: return "Videos"
			case .scripts: return "Scripts"
			case .thumbnailImage: return "Thumbnail Icon"
			}
		}
		
		var defaultMimeType: String {
			switch self {
			case .images: return "image/data"
			case .links: return "text/text"
			case .styleSheets: return "text/css"
			case .embed: return "/"
			case .videos: return "text/text"
			case .frames: return "/"
			case .scripts: return "text/javascript"
			case .unknown: return "data/data"
			default: return "image/data"
			}
		}
		
		var script: String {
			switch self {
			case .images: return "var tags = document.getElementsByTagName('img'); var urls = []; for (i = 0; i < tags.length; i++) { if (tags[i].src) { urls.push(tags[i].src) } else if (tags[i].attributes['data-original']) { urls.push(tags[i].attributes['data-original'].value) } }; urls"
			case .videos: return self.scriptToCollectTags("video", attribute: "src")
			case .links: return self.scriptToCollectTags("link", attribute: "href")
			case .frames: return self.scriptToCollectTags("iframe", attribute: "src")
				
			case .styleSheets: return "var tags = document.styleSheets; var css = []; for (i = 0; i < tags.length; i++) { if (tags[i].href) { css.push(tags[i].href) } else if (tags[i]['data-original']) { css.push(tags[i]['data-original'].value) }}; css"
				
			case .embed: return "var tags = document.getElementsByTagName('embed'); var urls = []; for (i = 0; i < tags.length; i++) { if (tags[i].src) { urls.push(tags[i].src) } }; urls"
			case .scripts: return "var tags = document.scripts; var js = []; for (i = 0; i < tags.length; i++) { if (tags[i].src) { js.push(tags[i].src) } }; js"
			case .unknown, .thumbnailImage: return ""
			}
		}
		
		func scriptToCollectTags(_ tag: String, attribute: String) -> String {
			return "var tags = document.getElementsByTagName('\(tag)'); var urls = []; for (i = 0; i < tags.length; i++) { urls.push(tags[i].\(attribute)) }; urls";
		}
		
		var tag: String? {
			switch self {
			case .images: return "img"
			case .links: return "link"
			case .frames: return "iframe"
			case .videos: return "video"
			case .scripts: return "script"
			case .embed: return "embed"
			case .styleSheets: return "style"
			case .unknown, .thumbnailImage: return nil
			}
		}

		var linkType: String? {
			switch self {
			case .styleSheets: return "stylesheet"
			default: return nil
			}
		}

		static let resourceOrder = [ResourceType.images, ResourceType.links, ResourceType.styleSheets, ResourceType.frames, ResourceType.scripts, ResourceType.styleSheets, ResourceType.embed]
	}
	
	class Resource: Equatable, Hashable, CustomStringConvertible {
		static var session = HTMLArchiver.defaultURLSession
		
		let url: URL
		let parentFrame: WebFrame
		let type: ResourceType
		var failed = false
		var error: Error?
		var storageURL: URL?
		var isPrimaryThumbnail: Bool = false
		var tempDirectory: URL { return self.parentFrame.tempDirectory }
		var string: String? { if let data = self.data { return String(data: data, encoding: String.Encoding.ascii) }; return nil }
		var isImage: Bool { return self.type == .images }
		
		var archiveDictionary: JSONDictionary? {
			if let data = self.data {
				var dict: JSONDictionary = ["WebResourceData": data, "WebResourceMIMEType": self.mimeType, "WebResourceURL": self.url.absoluteString ]
				
				if let response = self.response as? HTTPURLResponse {
					dict["WebResourceResponse"] = response.buildArchivedData(mimeType: self.mimeType)
				}
				
				return dict
			}
			return nil
		}
		
		public var mimeType: String = "data/data"
		var response: URLResponse?
		
		init?(thumbnailURL: URL, mainFrame: WebFrame, isPrimary: Bool) {
			self.hashValue = (thumbnailURL as NSURL).hash
			self.url = thumbnailURL
			self.isPrimaryThumbnail = isPrimary
			self.parentFrame = mainFrame
			type = .thumbnailImage
		}
		
		init?(url u: URL, frame: WebFrame, type t: ResourceType) {
			url = u
			type = t
			hashValue = (url as NSURL).hash
			parentFrame = frame
			if url.scheme == "data" { return nil }
		}
		
		func log(_ error: Error?, _ comment: String) {
			guard let err = error else { return }
			
			print("\(comment)\n\(err)")
		}
		
		func start() {
			let url = HTMLArchiver.forceHTTPS ? self.url.secureURL : self.url

			//if components.scheme == "http" { secureURL = NSURL(string: "https://proxy-nl.hide.me/go.php?u=\(secureURL.absoluteString)")! }
			var request = URLRequest(url: url)
			var headers = request.allHTTPHeaderFields ?? [:]
			headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_5) AppleWebKit/603.2.4 (KHTML, like Gecko) Version/10.1.1 Safari/603.2.4"
			if self.type == .images { headers["Accept"] = "image/webp,image/apng,image/*,*/*;q=0.8" }
			headers["Referrer"] = self.parentFrame.url.absoluteString
			headers["Origin"] = self.parentFrame.url.absoluteString
			request.allHTTPHeaderFields = headers
			
			let task = Resource.session.downloadTask(with: request, completionHandler: { location, response, error in
				self.log(error, "Problem loading resource: \(url)")
				
				if let resp = response as? HTTPURLResponse, resp.statusCode / 100 < 4 {
					self.failed = !self.saveDownload(at: location)
				} else {
					print("Download failed for \(self.url): \(response?.description ?? "")")
					self.failed = true
				}
				self.mimeType = response?.mimeType ?? self.type.defaultMimeType
				self.response = response
				
				self.error = error
				self.parentFrame.resourceFinished(self)
			})
			
			task.resume()
		}
		
		func saveDownload(at fileURL: URL?) -> Bool {
			guard let url = fileURL else { return false }
			let fileExtension = url.pathExtension
			let newURL = self.tempDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
			
			do {
				try FileManager.default.copyItem(at: url, to: newURL)
				self.storageURL = newURL
			} catch let error {
				self.log(error, "Error copying downloaded file")
				return false
			}
			return true
		}
		
		var data: Data? {
			if let url = self.storageURL {
				return try? Data(contentsOf: url)
			}
			return nil
		}
		
		var hashValue: Int
		func hash(into hasher: inout Hasher) { hasher.combine(self.hashValue) }
		var isStyleSheet: Bool { return self.mimeType.lowercased().contains("css") }
		var isHTML: Bool { return self.mimeType.lowercased().contains("html") }
		var isIFrame: Bool { return self.type == .frames }
		
		var description: String {
			if let data = self.data {
				return "\(self.type.description): \(data.count) bytes, \(self.url)"
			}
			return "\(self.type.description): \(self.url.path)"
		}
		
		static let relevantLinkTypes = [ "shortcut icon", "stylesheet", "manifest", "script" ]
		func extractImportedURLs() -> [URL] {
			guard self.isHTML || self.isStyleSheet else { return [] }
			guard let data = self.data, let source = String(data: data, encoding: String.Encoding.ascii) else { return [] }
			let pattern = self.isStyleSheet ? "url\\((?<url>[^)]*)\\)" : "<link.+?href=\"([^\\>]+)"
			do {
				let regex = try NSRegularExpression(pattern: pattern, options: [ .caseInsensitive])
				var urls: Set<URL> = []
				let hrefExtractor = try NSRegularExpression(pattern: "href=\"([^\"]+)", options: [ .caseInsensitive ])
				let relExtractor = try NSRegularExpression(pattern: "rel=\"([^\"]+)", options: [ .caseInsensitive ])
				
				let range = NSRange(location: 0, length: source.count)
				let matches = regex.matches(in: source, options: [.reportCompletion], range: range)
				for match in matches {
					let src = source as NSString
					var sub: String?
					if self.isStyleSheet {
						if match.range.length > 7 {
							sub = src.substring(with: NSRange(location: match.range.location + 4, length: match.range.length - 5))
						}
					} else {
						let hrefMatches = hrefExtractor.matches(in: source, options: [ .reportCompletion], range: match.range)
						let relMatches = relExtractor.matches(in: source, options: [ .reportCompletion], range: match.range)
						if hrefMatches.count > 0 && relMatches.count > 0 {
							let rel = src.substring(with: NSRange(location: relMatches[0].range.location + 5, length: relMatches[0].range.length - 5))
							if Resource.relevantLinkTypes.contains(rel) {
								sub = src.substring(with: NSRange(location: hrefMatches[0].range.location + 6, length: hrefMatches[0].range.length - 6))
							}
						}
					}
					if let sub = sub {
						let expanded = sub.removingPercentEncoding ?? sub
						if let url = expanded.expandURLRelativeTo(self.url) { urls.insert(url) }
					}
				}
				
				return Array(urls)
			} catch { return [] }
		}
		
	}
}

extension String {
	func expandURLRelativeTo(_ parent:	URL) -> URL? {
		let string = self.trimmingCharacters(in: CharacterSet(charactersIn: "\'\""))
		
		if self.hasPrefix("http") { return URL(string: string) }
		if string.hasPrefix("//") {
			return URL(string: "http:" + string)
		} else if string.hasPrefix("/") {
			guard let components = URLComponents(url: parent, resolvingAgainstBaseURL: true) else { return nil }
			guard let host = components.host, let scheme = components.scheme, let url = URL(string: "\(scheme)://\(host)\(string)") else { return nil }
			return url
		} else if string.hasPrefix("../") {
			var trimmed = parent.deletingLastPathComponent()
			if !string.hasSuffix("/") { trimmed = parent.deletingLastPathComponent() }
			return trimmed.appendingPathComponent(String(string[string.index(3)...]))
		} else if string.hasPrefix("http") {
			return URL(string: string)
		}
		return nil
	}
}

func ==(lhs: HTMLArchiver.Resource, rhs: HTMLArchiver.Resource) -> Bool {
	return lhs.url == rhs.url && lhs.type ≈≈ rhs.type
}

func ≈≈(lhs: HTMLArchiver.ResourceType, rhs: HTMLArchiver.ResourceType) -> Bool {
	if lhs == .links, rhs == .styleSheets { return true }
	if rhs == .links, lhs == .styleSheets { return true }
	
	return lhs == rhs
}

extension URL {
	var isSecure: Bool {
		if let components = URLComponents(url: self, resolvingAgainstBaseURL: true), components.scheme == "https" { return true }
		return false
	}
	
	var secureURL: URL {
		if var components = URLComponents(url: self, resolvingAgainstBaseURL: true), components.scheme == "http" {
			components.scheme = "https"
			return components.url ?? self
		}
		return self
	}
	
	var insecureURL: URL {
		if var components = URLComponents(url: self, resolvingAgainstBaseURL: true), components.scheme == "https" {
			components.scheme = "http"
			return components.url ?? self
		}
		return self
	}
}

extension HTTPURLResponse {
	enum Error: String, Swift.Error { case sourceDataNotFound, unableToExtractDictionary, unableToGetObjects, unableToGetResponse }
	func buildArchivedData(mimeType: String) -> Data? {
		do {
			guard var response = try ArchivedResponse(mimeType: mimeType) else { return nil }
			
	//		print("\(response.objects)")
			for (rawHeader, value) in self.allHeaderFields {
				guard let header = rawHeader as? String else { continue }
				response[header] = value
			}
			
			if let url = self.url?.absoluteString { response.url = url }
	//		print("\(response.objects)")
			return response.data
		} catch {
			
		}

		let archiver = NSKeyedArchiver(requiringSecureCoding: false)
		//					var headers = response.allHeaderFields as? [String: String] ?? [:]
		//					headers["Access-Control-Allow-Origin"] = "*"
		//					if let url = response.url, headers["Access-Control-Allow-Origin"] == nil {
		//						response = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: headers) ?? response
		//					}
		archiver.outputFormat = .binary
		archiver.encode(self, forKey: "WebResourceResponse")
		archiver.finishEncoding()
		let raw = archiver.encodedData
		
		do {
			guard let plist = try PropertyListSerialization.propertyList(from: raw, options: .mutableContainersAndLeaves, format: nil) as? NSMutableDictionary else { throw Error.unableToExtractDictionary }
			guard let objects = plist["$objects"] as? NSMutableArray, objects.count > 1, let root = objects[1] as? [String: Any] else { throw Error.unableToGetObjects }
			var newRoot: [String: Any] = [:]
			var propCount = 0
			
			var values: [Any] = []
			let keys = root.keys.sorted {
				guard let s0 = $0.intValueWithoutDollarSignPrefix else { return false }
				guard let s1 = $1.intValueWithoutDollarSignPrefix else { return false }
				return s0 < s1
			}
			for key in keys {
				guard let value = root[key] else { continue }
				if value is NSNumber || key.count < 4 {
					values.append(value)
				} else if key.count > 4 {
					newRoot[key] = value
				} else {
					newRoot["__nsurlrequest_proto_prop_obj_\(propCount)"] = value
					propCount += 1
				}
			}
			
			for i in 0..<values.count {
				newRoot["$\(i)"] = values[i]
			}
			
			objects[1] = newRoot
			plist["$objects"] = objects
			
			return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
		} catch {
			print("Error while archiving an HTTPURLResponse: \(error), \(self)")
		}
		return raw
	}
	
	struct ArchivedResponse {
		var propertyList: NSMutableDictionary!
		var objects: [Any] = []
		var responseHeaderKeys: [CFTypeRef] = []
		var responseHeaderValues: [CFTypeRef] = []
		var url: String = "" { didSet {
			self.objects[3] = self.url
		}}
		public var mimeType: String
		
		func starterData() throws -> Data {
			guard let url = Bundle(for: HTMLArchiver.self).url(forResource: "archived_response", withExtension: "dat") else { throw Error.sourceDataNotFound}
			return try Data(contentsOf: url)
		}
		
		init?(mimeType: String) throws {
			self.mimeType = mimeType
			guard let plist = try PropertyListSerialization.propertyList(from: try self.starterData(), options: .mutableContainersAndLeaves, format: nil) as? NSMutableDictionary else { throw Error.unableToExtractDictionary }
			guard let objects = plist["$objects"] as? [Any],
				objects.count > 30,
				let responseComponents = objects[8] as? [String: Any],
				let keys = responseComponents["NS.keys"] as? [CFTypeRef],
				let values = responseComponents["NS.objects"] as? [CFTypeRef]
			else { throw Error.unableToGetResponse }
			
			self.propertyList = plist
			self.objects = objects
			self.responseHeaderKeys = keys
			self.responseHeaderValues = values
			self.url = objects[3] as? String ?? ""
			self.objects[50] = mimeType
		}
		
		var data: Data? {
			let plist = self.propertyList!
			
			plist["$objects"] = self.objects
			
			do {
				return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
			} catch { }
			
			return try? self.starterData()
		}
		
		subscript(_ label: String) -> Any? {
			get {
				guard let index = self.indexForHeader(named: label) else { return nil }
				return self.objects[index]
			}
			
			set {
				guard let index = self.indexForHeader(named: label) else { return }
				self.objects[index] = newValue ?? ""
			}
		}
		
		func indexForHeader(named: String) -> Int? {
			var offset = 0
			for raw in self.responseHeaderKeys {
				guard let index = self.integerValue(for: raw) else { continue }
				if let string = self.objects[index] as? String, string == named {
					return self.integerValue(for: self.responseHeaderValues[offset])
				}
				offset += 1
			}
			return nil
		}
		
		func integerValue(for value: CFTypeRef) -> Int? {
			if let raw = "\(value)".trimmingCharacters(in: .init(charactersIn: "}")).components(separatedBy: " ").last { return Int(raw) }
			return nil
		}

	}
}

extension String {
	var intValueWithoutDollarSignPrefix: Int? {
		return Int(self.dropFirst())
	}
}
