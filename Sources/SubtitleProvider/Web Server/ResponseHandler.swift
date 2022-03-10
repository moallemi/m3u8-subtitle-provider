//
//  ResponseHandler.swift
//
//  Created by Reza Moallemi on 2/10/22.
//

import Foundation
import NIO
import NIOHTTP1

final class ResponseHandler: ChannelInboundHandler {
	typealias InboundIn = HTTPServerRequestPart
	typealias OutboundOut = HTTPServerResponsePart
	
	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let part = unwrapInboundIn(data)
		
		guard case let .head(head) = part else { return }
		
		let fileNames = (try? FileManager.default.contentsOfDirectory(
			atPath: FileManager.default.urlForCachesDirectory().path
		)) ?? []
		
		// replacing random query string
		let cleanUri = head.uri.replacingOccurrences(of: "(\\?.*)$", with: "", options: .regularExpression, range: nil)
		
		print("SERVER: \(cleanUri)")
		
		var response = Data()
		
		for name in fileNames where cleanUri.contains(name) {
			response = FileManager.default.contents(
				
				atPath: FileManager.default
					.urlForCachesDirectory()
					.appendingPathComponent(name)
					.path
			) ?? Data()
			break
		}
		
		if response.isEmpty {
			let content = "Invalid path"
			response = content.data(using: .utf8) ?? Data()
		}
		
		// set the headers
		var headers = HTTPHeaders()
		headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
		headers.add(name: "Content-Length", value: "\(response.count)")
		
		let responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
		context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
		
		// Set the data
		var buffer = context.channel.allocator.buffer(capacity: response.count)
		buffer.writeBytes(response)
		let body = HTTPServerResponsePart.body(.byteBuffer(buffer))
		context.writeAndFlush(wrapOutboundOut(body), promise: nil)
		context.close(promise: nil)
	}
}
