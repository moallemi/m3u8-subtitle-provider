//
//  StringExtensions.swift
//
//
//  Created by Saeed Taheri on 3/10/22.
//

import Foundation

extension String {
  func match(_ regex: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: regex) else {
      return []
    }

    let matches = regex.matches(
      in: self,
      options: [],
      range: NSRange(location: 0, length: utf16.count)
    )

    return matches.lazy.compactMap { result in
      if let range = Range(result.range, in: self) {
        return String(self[range])
      } else {
        return nil
      }
    }
  }
}
