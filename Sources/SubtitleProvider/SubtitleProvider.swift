import Foundation

public final class SubtitleProvider {
	private let host: String
	private let port: Int
	
	private let serverQueue = DispatchQueue(label: "com.m3u8.subtitle.provider.server.queue", qos: .background)
	private lazy var serverStartWorkItem = DispatchWorkItem { [host, port] in
		Server.start(host: host, port: port)
	}
		
	public init(host: String = "localhost", port: Int = 8888) {
		self.host = host
		self.port = port
		
		serverQueue.async(execute: serverStartWorkItem)
	}
		
	deinit {
		Server.stop()
		serverStartWorkItem.cancel()
	}
	
	public func m3u8WithSubtitles(
		_ subtitles: [Subtitle],
		originalM3U8: String,
		id: String = UUID().uuidString
	) async -> String {
		guard !subtitles.isEmpty else { return originalM3U8 }

		guard let downloadedFile = await downloadFile(from: originalM3U8, saveTo: "original.m3u8", in: id) else {
			return originalM3U8
		}

		var processedLines = processM3U8(originalURL: originalM3U8, downloadedFileURL: downloadedFile)
		
		for subtitle in subtitles {
			if let subtitleFileURL = await downloadFile(from: subtitle.url, saveTo: "\(subtitle.languageCode).txt", in: id) {
				processedLines.append("""
   #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",LANGUAGE="\(subtitle.languageCode)",NAME="\(subtitle.languageName)",AUTOSELECT=\(subtitle.isDefault ? "YES" : "NO"),DEFAULT=\(subtitle.isDefault ? "YES" : "NO"),URI="sub-\(subtitle.languageCode).m3u8"
   """)
				convertToVTT(srtFileURL: subtitleFileURL)
				buildM3U8SubtitleForLanguage(subtitle.languageCode, srtFileURL: subtitleFileURL)
			} else {
				continue
			}
		}
				
		saveContent(processedLines.joined(separator: "\r"), to: "merged.m3u8", in: id)

		return "http://\(host):\(port)/\(id)/merged.m3u8?\(UUID().uuidString)"
	}
	
	private func processM3U8(originalURL: String, downloadedFileURL: URL) -> [String] {
		let lastIndex = originalURL.index(after: originalURL.lastIndex(of: "/")!)
		let baseURL = originalURL[..<lastIndex]
		
		let fileURL = downloadedFileURL
		let content = try? String(contentsOf: fileURL, encoding: .utf8)
		let lines = content?.components(separatedBy: .newlines) ?? []
		var processedLines = [String]()
		for line in lines {
			if line.starts(with: "#EXT-X-STREAM-INF") {
				processedLines.append(line + ",SUBTITLES=\"subs\"")
			} else if !line.starts(with: "#"), line.hasSuffix(".m3u8") {
				processedLines.append("\(baseURL)\(line)")
			} else if line.starts(with: "#EXT-X-MEDIA"), line.contains("URI=\"") {
				processedLines.append(line.replacingOccurrences(of: "URI=\"", with: "AUTOSELECT=YES,DEFAULT=YES,URI=\"\(baseURL)"))
			} else if line != "" {
				processedLines.append(line)
			}
		}
		return processedLines
	}

	@discardableResult
	private func downloadFile(from url: String, saveTo fileName: String, in directory: String) async -> URL? {
		do {
			let (data, _) = try await URLSession.shared.download(from: URL(string: url)!)
			return saveContent(try String(contentsOf: data), to: fileName, in: directory)
		} catch {
			print("Failed to download file from \(url): \(error.localizedDescription).")
		}
		return nil
	}

	@discardableResult
	private func saveContent(_ contents: String, to fileName: String, in directory: String) -> URL? {
		let directoryURL = FileManager.default.urlForCachesDirectory().appendingPathComponent(directory)

		if !FileManager.default.fileExists(atPath: directoryURL.absoluteString) {
			do {
				try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
			} catch {
				print("Unable to create directory: \(directoryURL).\n\(error.localizedDescription)")
			}
		}

		do {
			let fileURL = directoryURL.appendingPathComponent(fileName)
			try contents.write(to: fileURL, atomically: true, encoding: .utf8)
			return fileURL
		} catch {
			print("Unable to create file: \(fileName) in directory: \(directory).\n\(error.localizedDescription)")
		}

		return nil
	}
		
	private func convertToVTT(srtFileURL: URL) {
		let content = try? String(contentsOf: srtFileURL, encoding: .utf8)
		let lines = content!.components(separatedBy: "\n")
		
		var processedLines = [String]()
		for (index, line) in lines.enumerated() {
			if line == "WEBVTT" {
				processedLines.append(line)
				processedLines.append("X-TIMESTAMP-MAP=MPEGTS:100000,LOCAL:00:00:00.000")
				continue
			}
			
			let subtitleCounter = Int(line.trimmingCharacters(in: [" ", "\u{FEFF}", "\r"]))
			if subtitleCounter != nil, index > 0, lines[index - 1] == "" || lines[index - 1] == "\r" || lines[index - 1] == "\n" {
				continue
			}
			if line.contains("-->") {
				processedLines.append(line.replacingOccurrences(of: ",", with: "."))
			} else {
				processedLines.append(line)
			}
		}

		saveContent(
			processedLines.joined(separator: "\n"),
			to: srtFileURL.deletingPathExtension().appendingPathExtension("vtt").lastPathComponent,
			in: srtFileURL.deletingLastPathComponent().lastPathComponent
		)
	}
	
	private func buildM3U8SubtitleForLanguage(_ languageCode: String, srtFileURL: URL) {
		let content = try? String(contentsOf: srtFileURL, encoding: .utf8)
		
		guard
			let timeParts = content?
				.match(#"--> (\d{2}:\d{2}:\d{2}(.\d{3}?.*)?)"#)
				.last?
				.components(separatedBy: "-->")
				.last?
				.components(separatedBy: ":")
				.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
				.compactMap(Double.init), timeParts.count == 3
		else {
			return
		}
		
		let duration = timeParts[0] * 3600.0 + timeParts[1] * 60.0 + timeParts[2]
		let durationInt = Int(duration.rounded(.up))
		
		let fileContent = """
 #EXTM3U
 #EXT-X-TARGETDURATION:\(durationInt)
 #EXT-X-VERSION:3
 #EXT-X-MEDIA-SEQUENCE:0
 #EXT-X-PLAYLIST-TYPE:VOD
 #EXTINF:\(duration)
 \(languageCode).vtt
 #EXT-X-ENDLIST
 """

		saveContent(
			fileContent,
			to: "sub-\(languageCode).m3u8",
			in: srtFileURL.deletingLastPathComponent().lastPathComponent
		)
	}
}
