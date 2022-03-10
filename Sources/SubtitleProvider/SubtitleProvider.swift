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
	
	public func m3u8WithSubtitles(_ subtitles: [Subtitle], originalM3U8: String) async -> String {
		guard !subtitles.isEmpty else { return originalM3U8 }

		await downloadFile(originalM3U8, saveTo: "original.m3u8")
		
		var processedLines = processOriginalM3U8(originalM3U8)
		
		for subtitle in subtitles {
			await downloadFile(subtitle.url, saveTo: "\(subtitle.languageCode).txt")
			processedLines.append("""
   #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",LANGUAGE="\(subtitle.languageCode)",NAME="\(subtitle.languageName)",AUTOSELECT=\(subtitle.isDefault ? "YES" : "NO"),DEFAULT=\(subtitle.isDefault ? "YES" : "NO"),URI="sub-\(subtitle.languageCode).m3u8"
   """)
			convertToVTT(srtFileName: "\(subtitle.languageCode).txt")
			buildM3U8SubtitleForLanguage(subtitle.languageCode)
		}
				
		saveContent(processedLines.joined(separator: "\r"), to: "merged.m3u8")
		
		return "http://\(host):\(port)/merged.m3u8?\(UUID().uuidString)"
	}
	
	private func processOriginalM3U8(_ originalUrl: String) -> [String] {
		let lastIndex = originalUrl.index(after: originalUrl.lastIndex(of: "/")!)
		let baseURL = originalUrl[..<lastIndex]
		
		let fileURL = FileManager.default.urlForCachesDirectory().appendingPathComponent("original.m3u8")
		let content = try? String(contentsOf: fileURL, encoding: .utf8)
		let lines = content!.components(separatedBy: .newlines)
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
	
	private func downloadFile(_ filePath: String, saveTo fileName: String) async {
		do {
			let (data, _) = try await URLSession.shared.download(from: URL(string: filePath)!)
			saveContent(try String(contentsOf: data), to: fileName)
		} catch {
			print("Unexpected error: \(error.localizedDescription).")
		}
	}
	
	private func saveContent(_ contents: String, to fileName: String) {
		let filename = FileManager.default.urlForCachesDirectory().appendingPathComponent(fileName)
		
		do {
			try contents.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
		} catch {
			print("Unexpected error: \(error).")
		}
	}
		
	private func convertToVTT(srtFileName: String) {
		let fileURL = FileManager.default.urlForCachesDirectory().appendingPathComponent(srtFileName)
		let content = try? String(contentsOf: fileURL, encoding: .utf8)
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
		saveContent(processedLines.joined(separator: "\n"), to: "\(srtFileName).vtt")
	}
	
	private func buildM3U8SubtitleForLanguage(_ languageCode: String) {
		let fileURL = FileManager.default.urlForCachesDirectory().appendingPathComponent("\(languageCode).txt")
		let content = try? String(contentsOf: fileURL, encoding: .utf8)
		
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
 \(languageCode).txt.vtt
 #EXT-X-ENDLIST
 """
		saveContent(fileContent, to: "sub-\(languageCode).m3u8")
	}
}
