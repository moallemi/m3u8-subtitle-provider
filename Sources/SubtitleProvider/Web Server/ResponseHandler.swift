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

    var response = Data()

    guard case let .head(head) = part else {
      return
    }

    // replacing random query string
    var urlComponents = URLComponents(string: head.uri)
    urlComponents?.queryItems = nil
    guard let cleanURL = urlComponents?.url else {
      outputResponse(response, context: context)
      return
    }

    print("[GET]: \(cleanURL)")

    response = FileManager.default.contents(
      atPath: FileManager.default.urlForCachesDirectory().appendingPathComponent(cleanURL.path).path
    ) ?? Data()

    outputResponse(response, context: context)
  }

  private func outputResponse(_ data: Data, context: ChannelHandlerContext) {
    var headers = HTTPHeaders()
    headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
    headers.add(name: "Content-Length", value: "\(data.count)")

    let status: HTTPResponseStatus

    if data.isEmpty {
      status = .noContent
    } else {
      status = .ok
    }

    let responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1), status: status, headers: headers)
    context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

    var buffer = context.channel.allocator.buffer(capacity: data.count)
    buffer.writeBytes(data)
    let body = HTTPServerResponsePart.body(.byteBuffer(buffer))
    context.writeAndFlush(wrapOutboundOut(body), promise: nil)
    context.close(promise: nil)
  }
}
