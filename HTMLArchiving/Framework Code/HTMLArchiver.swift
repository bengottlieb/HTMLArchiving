//
//  HTMLArchiver.swift
//  Archivist
//
//  Created by Ben Gottlieb on 1/10/16.
//  Copyright © 2016 Stand Alone, Inc. All rights reserved.
//

import WebKit
import Plug
import ParseHTML
import Gulliver

public typealias HTMLArchiverProgressCallback = ((Double) -> Void)
public typealias ArchiveCompletionClosure = ((HTMLArchive?, Error?) -> Void)

open class HTMLArchiver {
	enum ArchiveError: Error { case cancelled, failedToGetHTML }
	enum State { case idle, waitingForHTML, starting, loadingHTML, parsing, loadingResources, complete }
	
	var bundle: BundledPageData!
	var html: String?
	var data: Data?
	let url: URL
	var state = State.idle
	var text: String?
	var tempDirectory: URL!
	var progressCallback: HTMLArchiverProgressCallback?
	
	var mainFrame: WebFrame?
	var archiveResults: HTMLArchive?
	var startDocket: Docket!
	var resourceURLs: [ResourceType: [String]] = [:]
	let fetchHTMLFromWebView = false		// some sites seem to be having problems if we fetch the webview-preprocessed HTML. We should grab directly from the site when possible
	
	public init?(webView: WKWebView, url: URL? = nil, progressCallback: HTMLArchiverProgressCallback? = nil) {
		var targetURL = webView.url ?? URL.blank
		if targetURL == URL.blank { targetURL = url ?? URL.blank }
		self.url = targetURL
		self.progressCallback = progressCallback
		
		if webView.url == nil { return nil }
		if !self.setupTempDirectory() { return nil }
		self.state = .waitingForHTML

		self.startDocket = Docket("webviewArchiveProgress") {
			let shouldArchive = self.state == .starting
			self.state = .idle
			if shouldArchive { self.beginArchive() }
		}
		
		if self.fetchHTMLFromWebView {
			self.startDocket.increment(tag: "html")
			webView.fetchHTML { html in
				self.html = html
				self.startDocket.decrement(tag: "html")
			}
		}
		
		self.startDocket.increment(tag: "stylesheets")
		self.startDocket.increment(tag: "touchIcon")

		webView.evaluateJavaScript("document.body.innerText") { text, error in
			if let content = text as? String {
				self.text = content
			}
		}
		
		webView.evaluateJavaScript("var a = []; for (i = 0; i < document.styleSheets.length; i++) { if (document.styleSheets[i].href != null) a.push(document.styleSheets[i].href); }; a") { results, error in
			if let urls = results as? [String] {
				self.resourceURLs[.styleSheets] = urls
			}
			self.startDocket.decrement(tag: "stylesheets")
		}
		
		webView.evaluateJavaScript(WKWebView.findFavIconScript) { results, error in
			if let raw = results as? String, let url = raw.url(basedOn: self.url), let mainFrame = self.mainFrame {
				mainFrame.queue(resource: Resource(thumbnailURL: url, mainFrame: mainFrame, isPrimary: true))
				print("Found touch icon: \(url)")
			} else {
				print("No thumbnail found")
			}
			self.startDocket.decrement(tag: "touchIcon")
		}
	}
	
	public init?(url: URL, html: String? = nil, progressCallback: HTMLArchiverProgressCallback? = nil) {
		self.html = html
		self.url = url
		self.progressCallback = progressCallback
		if !self.setupTempDirectory() { return nil }
	}
	
	public convenience init?(info: BundledPageData, progressCallback: HTMLArchiverProgressCallback? = nil) {
		self.init(url: info.url, html: info.html, progressCallback: progressCallback)
		self.bundle = info
	}
	
	func setupTempDirectory() -> Bool {
		self.tempDirectory = FileManager.tempDirectoryURL.appendingPathComponent("archiver-scratch-\(UUID().uuidString)")
		do {
			try FileManager.default.createDirectory(at: self.tempDirectory, withIntermediateDirectories: true, attributes: nil)
		} catch let error {
			ErrorLogger.log(error, "Failed to set up temporary directory for archiving")
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
		if self.state != .idle {
			if self.state == .waitingForHTML { self.state = .starting }
			return
		}
		
		self.beginArchive()
	}
	
	func beginArchive() {
		if self.html == nil {	//|| self.data == nil {
			self.state = .loadingHTML
			guard let connection = Connection(method: .GET, url: self.url) else {
				self.fail(with: ArchiveError.failedToGetHTML)
				
				return
			}
			connection.addHeader(header: Plug.Header.userAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Safari/604.1.38"))
			connection.addHeader(header: Plug.Header.accept(["*/*"]))
			connection.addHeader(header: Plug.Header.acceptEncoding("gzip;q=1.0,compress;q=0.5"))

			connection.completion { conn, data in
				self.data = data.data
				if let html = data.data.string {
					self.html = html
					self.startParse()
				} else {
					self.fail(with: conn.resultsError ?? ArchiveError.failedToGetHTML)
				}
			}.error { conn, error in
				self.fail(with: error)
			}
			
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
