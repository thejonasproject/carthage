//
//  Build.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import ReactiveCocoa

public struct BuildCommand: CommandType {
	public let verb = "build"
	public let function = "Build the project in the current directory"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(BuildOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return self.openTemporaryLogFile()
					.map { (stdoutHandle, temporaryURL) -> ColdSignal<()> in
						let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!

						let (stdoutSignal, buildSignal) = buildInDirectory(directoryURL, withConfiguration: options.configuration, onlyScheme: options.scheme)
						let disposable = stdoutSignal.observe { data in
							stdoutHandle.writeData(data)
						}

						return buildSignal
							.then(.empty())
							.on(subscribed: {
								println("xcodebuild output can be found in \(temporaryURL.path!)\n")
							}, disposed: {
								disposable.dispose()
							})
					}
					.merge(identity)
			}
			.merge(identity)
			.wait()
	}

	/// Opens a temporary file for logging, returning the handle and the URL to
	/// the file on disk.
	private func openTemporaryLogFile() -> ColdSignal<(NSFileHandle, NSURL)> {
		return ColdSignal.lazy {
			var temporaryDirectoryTemplate: ContiguousArray<CChar> = NSTemporaryDirectory().stringByAppendingPathComponent("carthage-xcodebuild.XXXXXX.log").nulTerminatedUTF8.map { CChar($0) }
			let logFD = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> Int32 in
				return mkstemps(template.baseAddress, 4)
			}

			if logFD < 0 {
				return .error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String.fromCString(ptr.baseAddress)!
			}

			let stdoutHandle = NSFileHandle(fileDescriptor: logFD, closeOnDealloc: true)
			let temporaryURL = NSURL.fileURLWithPath(temporaryPath, isDirectory: false)!
			return .single((stdoutHandle, temporaryURL))
		}
	}
}

private struct BuildOptions: OptionsType {
	let configuration: String
	let scheme: String?

	static func create(configuration: String)(scheme: String) -> BuildOptions {
		return self(configuration: configuration, scheme: (scheme.isEmpty ? nil : scheme))
	}

	static func evaluate(m: CommandMode) -> Result<BuildOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build")
			<*> m <| Option(key: "scheme", defaultValue: "", usage: "a scheme to build (if not specified, all schemes will be built)")
	}
}