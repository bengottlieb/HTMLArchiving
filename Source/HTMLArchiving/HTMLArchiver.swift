//
//  HTMLArchiver.swift
//  Archivist
//
//  Created by Ben Gottlieb on 1/10/16.
//  Copyright © 2016 Stand Alone, Inc. All rights reserved.
//

import WebKit
import Studio

public typealias HTMLArchiverProgressCallback = ((Double) -> Void)
public typealias ArchiveCompletionClosure = ((HTMLArchive?, Error?) -> Void)

open class HTMLArchiver {
	enum ArchiveError: Error { case cancelled, failedToGetHTML }
	enum State { case idle, waitingForHTML, waitingForCookies, starting, loadingHTML, parsing, loadingResources, complete }
	
	public var bundle: BundledPageData!
	var html: String?
	var data: Data?
	public let url: URL
	var state = State.idle
	var text: String?
	var tempDirectory: URL!
	var progressCallback: HTMLArchiverProgressCallback?
	var session = URLSession.shared
	var isPrivate = false

	var cookies: [HTTPCookie] = []
	var mainFrame: WebFrame?
	var archiveResults: HTMLArchive?
    let dispatchGroup = DispatchGroup()

	var resourceURLs: [ResourceType: [String]] = [:]
	let fetchHTMLFromWebView = false		// some sites seem to be having problems if we fetch the webview-preprocessed HTML. We should grab directly from the site when possible
	
	public init?(webView: WKWebView, url: URL? = nil, private isPrivate: Bool = false, progressCallback: HTMLArchiverProgressCallback? = nil) {
		var targetURL = webView.url ?? URL.blank
		if targetURL == URL.blank { targetURL = url ?? URL.blank }
		self.url = targetURL
		self.progressCallback = progressCallback
		self.isPrivate = isPrivate
		
		if webView.url == nil { return nil }
		if !self.setupTempDirectory() { return nil }

		if self.fetchHTMLFromWebView {
			self.state = .waitingForHTML
			self.dispatchGroup.enter()
			webView.fetchHTML { html in
				self.html = html
                self.dispatchGroup.leave()
			}
		} else {
			if #available(OSXApplicationExtension 10.13, iOS 11, *) {
				self.state = .waitingForCookies
                self.dispatchGroup.enter()
				WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
					self.cookies = cookies
                    self.dispatchGroup.leave()
				}
			}
		}
		
        self.dispatchGroup.enter()
	//	self.startDocket.increment(tag: "touchIcon")

		webView.evaluateJavaScript("document.body.innerText") { text, error in
			if let content = text as? String {
				self.text = content
			}
		}
		
		webView.evaluateJavaScript("var a = []; for (i = 0; i < document.styleSheets.length; i++) { if (document.styleSheets[i].href != null) a.push(document.styleSheets[i].href); }; a") { results, error in
			if let urls = results as? [String] {
				self.resourceURLs[.styleSheets] = urls
			}
            self.dispatchGroup.leave()
		}
		
        self.dispatchGroup.notify(queue: .main) {
            self.beginArchive()
        }
		
//		webView.evaluateJavaScript(WKWebView.findFavIconScript) { results, error in
//			if let raw = results as? String, let url = raw.url(basedOn: self.url), let mainFrame = self.mainFrame {
//				mainFrame.queue(resource: Resource(thumbnailURL: url, mainFrame: mainFrame, isPrimary: true))
//				print("Found touch icon: \(url)")
//			} else {
//				print("No thumbnail found")
//			}
//			self.startDocket.decrement(tag: "touchIcon")
//		}
	}
	
	public convenience init?(info: BundledPageData, progressCallback: HTMLArchiverProgressCallback? = nil) {
		self.init(url: info.url, html: info.html, progressCallback: progressCallback)
		self.bundle = info
	}
	
	public init?(url: URL, html: String? = nil, private isPrivate: Bool = false, progressCallback: HTMLArchiverProgressCallback? = nil) {
		self.html = html
		self.isPrivate = isPrivate
		self.url = url
		self.progressCallback = progressCallback
		if !self.setupTempDirectory() { return nil }
        self.dispatchGroup.enter()
        self.dispatchGroup.notify(queue: .main) {
            self.beginArchive()
        }
	}
	
	func setupTempDirectory() -> Bool {
		self.tempDirectory = FileManager.tempDirectory.appendingPathComponent("archiver-scratch-\(UUID().uuidString)")
		do {
			try FileManager.default.createDirectory(at: self.tempDirectory, withIntermediateDirectories: true, attributes: nil)
		} catch {
			//ErrorLogger.log(error, "Failed to set up temporary directory for archiving")
		}
		return true
	}
	
	var propertyList: [String: Any]? {
		return self.mainFrame?.propertyList
	}
	
	var archiveCompleteBlocks: [ArchiveCompletionClosure] = []
	
	public func cancel() {
		self.fail(with: ArchiveError.cancelled)
	}
	
	open func reset() {
		self.archiveResults = nil
	}
	
	open func archive(_ completion: @escaping ArchiveCompletionClosure) {
		if let results = self.archiveResults {
			completion(results, nil)
			return
		}

		self.archiveCompleteBlocks.append(completion)
        self.dispatchGroup.leave()
	}
	
	func beginArchive() {
		if self.html == nil {	//|| self.data == nil {
			self.state = .loadingHTML
			let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Safari/604.1.38"
			
			var request = URLRequest(url: self.url)
			
			request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
			request.addValue("*/*", forHTTPHeaderField: "Accept")
			request.addValue("gzip;q=1.0,compress;q=0.5", forHTTPHeaderField: "Accept-Encoding")
			request.httpShouldHandleCookies = !self.isPrivate

			let task = self.session.dataTask(with: request) { data, response, error in
				if let err = error {
					self.fail(with: err)
					return
				}
				self.data = data
                if let d = data, let html = String(data: d, encoding: .utf8) {
					self.html = html
					self.startParse()
				} else {
					self.fail(with: ArchiveError.failedToGetHTML)
				}
			}
			task.resume()
		} else {
			self.startParse()
		}
	}
	
	func startParse() {
		self.state = .parsing
		DispatchQueue.main.async { self.setupMainFrame() }
	}
	
	func setupMainFrame() {
		guard let html = self.html else { return }
		self.mainFrame = self.bundle != nil ? WebFrame(bundle: self.bundle, tempDirectory: self.tempDirectory) : WebFrame(html: html, url: self.url, tempDirectory: self.tempDirectory, resourceURLs: self.resourceURLs)
		self.mainFrame?.data = self.data
		self.mainFrame?.progressCallback = self.progressCallback
		self.mainFrame?.downloadResources {
			var data: Data!
			
			autoreleasepool {
				if let plist = self.propertyList {
					data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
				}
			}

			var meta: [String: String] = [:]
				
			if self.bundle != nil {
				if let title = self.bundle.title { meta["title"] = title }
				if let author = self.bundle.author { meta["author"] = author }
				if let blurb = self.bundle.desc { meta["blurb"] = blurb }
				if let keywords = self.bundle.keywords { meta["keywords"] = keywords }
			} else {
				if let title = self.mainFrame?.title { meta["title"] = title }
				if let author = self.mainFrame?.doc?.metaContent(forProperty: "author") { meta["author"] = author }
				if let blurb = self.mainFrame?.doc?.metaContent(forProperty: "description") { meta["blurb"] = blurb }
				if let keywords = self.mainFrame?.doc?.metaContent(forProperty: "keywords") { meta["keywords"] = keywords }
			}

			self.succeed(data: data, meta: meta)
		}
	}
	
	func fail(with error: Error?) {
		self.archiveCompleteBlocks.forEach { $0(nil, error) }
	}
	
	func succeed(data: Data, meta: [String: String]) {
		let dataType = self.data?.fileType ?? .unknown
		let title = self.mainFrame?.title ?? NSLocalizedString("Untitled", comment: "Untitled")
		
		if let pdfData = self.mainFrame?.framePDFData {
			self.archiveResults = HTMLArchive(url: self.url, data: pdfData, meta: meta, text: nil, title: title, thumbnailImage: self.mainFrame?.thumbnailImage)
		} else if dataType == .pdf || dataType == .jpeg || dataType == .png {
			self.archiveResults = HTMLArchive(url: self.url, data: self.data!, meta: meta, text: nil, title: title, thumbnailImage: self.mainFrame?.thumbnailImage)
		} else {
			self.archiveResults = HTMLArchive(url: self.url, data: data, meta: meta, text: self.text, title: title, thumbnailImage: self.mainFrame?.thumbnailImage)
		}
		
		self.archiveResults?.originalURL = self.url
		self.archiveCompleteBlocks.forEach { $0(self.archiveResults, nil) }
	}

	static var defaultURLSession: URLSession = {
		let config = URLSessionConfiguration.default
		
		config.timeoutIntervalForRequest = 5.0
		//config.requestCachePolicy = .ReturnCacheDataDontLoad
		
		let session = URLSession(configuration: config, delegate: ArchiverSessionDelegate.defaultDelegate, delegateQueue: nil)
		
		return session
	}()
	
}

class ArchiverSessionDelegate: NSObject, URLSessionDataDelegate {
	static let defaultDelegate = ArchiverSessionDelegate()

	
	@objc func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		completionHandler(.useCredential, nil)
	}
}
