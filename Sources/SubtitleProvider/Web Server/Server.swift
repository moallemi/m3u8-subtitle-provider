//
//  Server.swift
//
//  Created by Reza Moallemi on 2/10/22.
//

import NIOCore
import NIOPosix

final class Server {
	private static var group: MultiThreadedEventLoopGroup?
	
	static func start(host: String, port: Int) {
		do {
			if group != nil {
				return
			}
			let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
			self.group = group
			
			let bootstrap = ServerBootstrap(group: group)
				.serverChannelOption(ChannelOptions.backlog, value: 256)
				.serverChannelOption(ChannelOptions.socket(
					SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR
				), value: 1)
				.childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
				.childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
				.childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
				.childChannelInitializer { channel in
					channel.pipeline.configureHTTPServerPipeline()
						.flatMap {
							channel.pipeline.addHandler(ResponseHandler())
						}
				}
			
			let channel = try bootstrap
				.bind(host: host, port: port)
				.wait()
			
			guard channel.localAddress != nil else {
				fatalError("Unable to bind to \(host) at port \(port)")
			}
			
			try channel.closeFuture.wait()
		} catch {
			print("An error happened \(error.localizedDescription)")
		}
	}
	
	public static func stop() {
		do {
			try group?.syncShutdownGracefully()
			group = nil
		} catch {
			print("An error happened \(error.localizedDescription)")
		}
	}
}
