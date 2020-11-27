//
//  Data+Extension.swift
//  HTMLArchiving
//
//  Created by Ben Gottlieb on 11/18/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

import Foundation

public extension Data {
    var fileType: FileType? {
        if self.count < 8 { return nil }

        return self.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            if bytes[0] == 0x50 && bytes[1] == 0x48 {
                if bytes[2] == 0x03 && bytes[3] == 0x04 { return .zip }
                if bytes[2] == 0x01 && bytes[3] == 0x02 { return .zip }
            }
            
            if bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 && bytes[4] == 0x2D { return .pdf }
            
            if bytes[0] == 0x62 && bytes[1] == 0x76 && bytes[2] == 0x78 && bytes[3] == 0x32 { return .lzf }
            
            if bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71 && bytes[4] == 13 && bytes[5] == 10 && bytes[6] == 26 && bytes[7] == 10 { return .png }
            
            if bytes[0] == 255 && bytes[1] == 216 {
                if bytes[self.count - 2] == 255 && bytes[self.count - 1] == 217 {
                    return .jpeg
                }
            }
            
            if bytes[0] == 71 && bytes[1] == 73 && bytes[2] == 70 && bytes[3] == 56 { return .gif }
            
            return nil
        }
    }

    struct FileType: Equatable {
        let rawValue: String
        
        init(_ rawValue: String) { self.rawValue = rawValue }
        
        public static let unknown = FileType("*")
        public static let gif = FileType("gif")
        public static let png = FileType("png")
        public static let jpeg = FileType("jpeg")
        public static let zip = FileType("zip")
        public static let lzf = FileType("lzf")
        public static let pdf = FileType("pdf")
        
        public static func ==(lhs: FileType, rhs: FileType) -> Bool {
            return lhs.rawValue == rhs.rawValue
        }
    }

}
