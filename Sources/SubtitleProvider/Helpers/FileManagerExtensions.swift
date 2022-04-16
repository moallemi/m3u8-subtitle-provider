//
//  FileManagerExtensions.swift
//
//
//  Created by Saeed Taheri on 3/10/22.
//

import Foundation

extension FileManager {
  func urlForCachesDirectory() -> URL {
    let paths = urls(for: .cachesDirectory, in: .userDomainMask)
    return paths[0]
  }
}
