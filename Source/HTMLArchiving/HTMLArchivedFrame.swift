//
//  HTMLArchivedFrame.swift
//  Archivist
//
//  Created by Ben Gottlieb on 1/10/16.
//  Copyright © 2016 Stand Alone, Inc. All rights reserved.
//

import WebKit
import Plug
import ParseHTML
import Gulliver
import CrossPlatformKit

extension HTMLArchiver {
	class WebFrame: Hashable {
		let html: String
		let url: URL
		let queue = DispatchQueue(label: "frame_queue", attributes: [])
		var hashValue: Int { return self.html.hash }
		func hash(into hasher: inout Hasher) { self.html.hash(into: &hasher) }
		var readyToExtract = false
		var resourceURLs: [ResourceType: [String]] = [:]
		var doc: HTMLDocument?
		var title: String?
		var thumbnailImage: UXImage!
		var parentFrame: WebFrame?
		var totalCount = AtomicValue(0)
		var successCount = AtomicValue(0)
		var failureCount = AtomicValue(0)
		let tempDirectory: URL
		var percentageComplete: Double {
			let totalCount = self.aggregateTotalCount
			return totalCount > 0 ? (Double(self.aggregateCompletedCount) / Double(totalCount)) : 0
		}
		
		init(html raw: String, data: Data? = nil, url incomingURL: URL, parent: WebFrame? = nil, tempDirectory: URL? = nil, resourceURLs: [ResourceType: [String]] = [:]) {
			self.html = raw
			self.resourceURLs = resourceURLs
			self.data = data
			self.url = incomingURL
			self.tempDirectory = parent?.tempDirectory ?? tempDirectory!
			self.doc = HTMLDocument(string: self.html)
			self.readyToExtract = true
			self.extractResources()
			self.downloadResources()
			self.parentFrame = parent
			if parent == nil { self.checkForThumbnailImage() }
		}
		
		func checkForThumbnailImage() {
			var urlString: String?
			
			guard let links = self.doc?.nodes(matchingSelector: "link") else { return }
			var isPrimary = false
			
			for link in links {
				if link.attributes["rel"] == "apple-touch-icon", let string = link.attributes["href"] {
					urlString = string
					isPrimary = true
				} else if link.attributes["rel"]?.lowercased() == "shortcut icon", let string = link.attributes["href"], urlString == nil {
					urlString = string
				}
			}
			
			if let raw = urlString, let url = raw.url(basedOn: self.url) {
				self.queue(resource: Resource(thumbnailURL: url, mainFrame: self, isPrimary: isPrimary))
			}

		}
		
		init(bundle: BundledPageData, tempDirectory: URL) {
			self.html = bundle.html
			self.url = bundle.url as URL
			self.tempDirectory = tempDirectory
			
			self.resourceURLs = [
				.images: bundle.images,
				.links: bundle.links,
				.frames: bundle.frames,
				.styleSheets: bundle.stylesheets,
				.videos: bundle.videos,
				.scripts: bundle.scripts
			]
			
			self.downloadResources()
		}
		
		var frameSingleImageData: Data? {
			if self.completedResources.count == 1, let resource = self.completedResources.first, resource.isImage {
				return resource.data
			}
			return nil
		}
		
		var framePDFData: Data? {
			if self.completedResources.count == 1, let resource = self.completedResources.first, let data = resource.data, data.fileType == .pdf {
				return resource.data
			}
			return nil
		}
		
		var resourceDownloadCompletion: (() -> Void)?
		var currentResourceType = ResourceType.images
		var subframes: [WebFrame] = []
		var progressCallback: HTMLArchiverProgressCallback?
		var data: Data?
		
		func updateCompletionPercentage() {
			DispatchQueue.main.async {
				self.progressCallback?(self.percentageComplete)
				self.parentFrame?.updateCompletionPercentage()
			}
		}
		
		func incrementTotalCount() { self.totalCount.value += 1; self.updateCompletionPercentage() }
		func incrementSuccessCount() { self.successCount.value += 1; self.updateCompletionPercentage() }
		func incrementFailureCount() { self.failureCount.value += 1; self.updateCompletionPercentage() }
		
		var aggregateTotalCount: Int {
			var count = self.totalCount.value
			for frame in self.subframes { count += frame.aggregateTotalCount }
			return count
		}

		var aggregateCompletedCount: Int {
			var count = self.successCount.value + self.failureCount.value
			for frame in self.subframes { count += frame.aggregateCompletedCount }
			return count
		}

		func downloadResources(_ completion: (() -> Void)? = nil) {
			self.queue.async {
				self.resourceDownloadCompletion = completion
				
				for (type, urls) in self.resourceURLs {
					for raw in urls {
						if let url = raw.expandURLRelativeTo(self.url), (url != self.url || (type != .frames && type != .links)), let res = Resource(url: url, frame: self, type: type) {
							self.queue(resource: res)
						}
					}
				}
				
				self.queue.async {
					self.continueDownload()
				}
			}
		}
		
		func metaTag(_ name: String) -> String? {
			let tags = self.doc?.nodes(matchingSelector: "meta") ?? []
			for tag in tags {
				if tag.attributes["itemprop"] == name { return tag.attributes["content"] }
				if tag.attributes["name"] == name { return tag.attributes["content"] }
			}
			return nil
		}
		
		func linkTags(_ name: String) -> [String] {
			let tags = self.doc?.nodes(matchingSelector: "link") ?? []
			var results: [String] = []
			for tag in tags {
				if tag.attributes["rel"] == name, let ref = tag.attributes["href"]?.url(basedOn: self.url)?.absoluteString, !results.contains(ref) {
					results.append(ref)
				}
			}
			return results
		}
		
		func extractResources() {
			//if self.html.characters.count > 0 { return }			// DEBUG: Disable resource extraction
			
			if let titleNode = self.doc?.firstNode(matchingSelector: "title") {
				self.title = titleNode.textContent
			} else if let title = self.doc?.metaContent(forProperty: "title") ?? self.doc?.metaContent(forProperty: "og:title") {
				self.title = title
			}
			
			for type in ResourceType.resourceOrder {
				var urlStrings: Set<String> = Set(self.resourceURLs[type] ?? [])
				if let tag = type.tag, let found = self.doc?.nodes(matchingSelector: tag) {
					urlStrings = urlStrings.union((found.compactMap { node in return node.resourceURLBased(on: self.url)?.absoluteString }))
				}
				
				if let linkType = type.linkType {
					urlStrings = urlStrings.union(self.linkTags(linkType))
				}
				
				self.resourceURLs[type] = Array(urlStrings)
			}
			
			for tag in self.doc?.nodes(withStyleTag: "background-image") ?? [] {
				let style = tag.parsedStyleTag
				
				if let background = style["background-image"] as? String, let urlfrag = background.urlFragment, let url = URL(string: urlfrag, relativeTo: self.url) {
					self.resourceURLs[.images]?.append(url.absoluteString)
				}
			}
		}
		
		var resourceList: [JSONDictionary] {
			var array: [JSONDictionary] = []
			
			for resource in self.completedResources {
				if let dict = resource.archiveDictionary {
					array.append(dict)
				}
			}
			return array
		}
		
		var propertyList: [String: Any]? {
			if let main = self.mainResource {
				var list: [String: Any] = [
					"WebMainResource": main,
					"WebSubresources": self.resourceList
				]
				
				if let subs = self.subframeArchives { list["WebSubframeArchives"] = subs }
				return list
			}
			return nil
		}
		
		var subframeArchives: [[String: Any]]? {
			var results: [[String: Any]] = []
			
			for subFrame in self.subframes {
				if let plist = subFrame.propertyList {
					results.append(plist)
				}
			}
			
			return results.count > 0 ? results : nil
		}
		
		var mainResource: JSONDictionary? {
			if let data = self.data ?? self.html.data(using: String.Encoding.utf8) {
				return [
					"WebResourceMIMEType": "text/html",
					"WebResourceData": data,
					"WebResourceTextEncodingName": "UTF-8",
					"WebResourceFrameName": "",
					"WebResourceURL": self.url.absoluteString
				]
			}
			return nil
		}
				
		var pendingResources: Set<Resource> = []
		var completedResources: Set<Resource> = []
		var pendingSubFrames: Set<WebFrame> = []
		
		func resourceFinished(_ resource: Resource) {
			self.queue.async {
				self.pendingResources.remove(resource)
				
				if resource.failed {
					self.incrementFailureCount()
				} else {
					self.incrementSuccessCount()
				}
				
				if resource.isIFrame {
					//print("Adding an iframe from \(resource.url)")
					if let html = resource.string , !html.isEmpty {
						let frame = WebFrame(html: html, data: resource.data, url: resource.url, parent: self)
						self.subframes.append(frame)
						self.pendingSubFrames.insert(frame)
						frame.downloadResources {
							self.queue.async {
								self.pendingSubFrames.remove(frame)
								self.continueDownload()
							}
						}
                    } else {
						self.continueDownload()
                    }
				} else if resource.type == .thumbnailImage {
					if self.thumbnailImage == nil || resource.isPrimaryThumbnail, let data = resource.data, let image = UXImage(data: data) {
						self.thumbnailImage = image
					}
				} else {
					for url in resource.extractImportedURLs() {
						if let child = Resource(url: url, frame: self, type: .unknown) , !self.pendingResources.contains(child) && !self.completedResources.contains(child) {
							self.queue(resource: child)
						}
						//_ = resource.extractImportedURLs()
					}
					if resource.failed {
						print("\(resource.url) failed \(String(describing: resource.error))")
					} else {
						self.completedResources.insert(resource)
					}
				}
				
				self.continueDownload()
			}
		}
		
		func queue(resource res: Resource?) {
			guard let resource = res else { return }
			self.queue.async {
				if self.pendingResources.contains(resource) || self.completedResources.contains(resource) { return }
				var set = self.pendingResources
				set.insert(resource)
				self.pendingResources = set
				resource.start()
				self.incrementTotalCount()
			}
		}
		
		func continueDownload() {
			if self.pendingResources.count == 0 {
				if self.pendingSubFrames.count == 0 {
					self.resourceDownloadCompletion?()
					self.resourceDownloadCompletion = nil
				}
			}
		}
	}
}

func ==(lhs: HTMLArchiver.WebFrame, rhs: HTMLArchiver.WebFrame) -> Bool {
	return lhs.url == rhs.url
}


extension String {
	func url(basedOn: URL) -> URL? {
		if self.hasPrefix("//"), let scheme = basedOn.scheme {
			let components = self.components(separatedBy: "?")
			guard let server = components.first else { return nil }
			var raw = scheme + ":" + server
			if components.count > 1, let path = components.last { raw += "?" + path.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) }
			return URL(string: raw)
		}
		return URL(string: self)
	}
}
