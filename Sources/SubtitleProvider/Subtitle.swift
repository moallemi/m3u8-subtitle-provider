//
//  Subtitle.swift
//  
//
//  Created by Saeed Taheri on 3/10/22.
//

import Foundation

public struct Subtitle {
	let languageCode: String
	let url: String
	let isDefault: Bool
	
	public init(languageCode: String, url: String, isDefault: Bool = false) {
		self.languageCode = languageCode
		self.url = url
		self.isDefault = isDefault
	}
}

extension Subtitle {
	var languageName: String {
		let locale = NSLocale(localeIdentifier: "\(languageCode.prefix(2))_IR")
		return locale.displayName(forKey: .languageCode, value: languageCode) ?? languageCode
	}
}
