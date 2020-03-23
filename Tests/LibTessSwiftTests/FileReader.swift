//
//  FileReader.swift
//  LogParser
//
//  Created by Luiz Fernando Silva on 10/01/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

import Foundation

enum StreamReaderError: Error {
    case couldNotLoad
}

/// File reader fit for reading from files with a high capacity output.
/// Provides no buffering of data (i.e. cannot peek).
final class FileReader {
    
    var fileContents: String
    var lines: [String]
    var currentLine = 0
    
    var isEndOfStream: Bool {
        return currentLine == lines.count
    }
    
    init(fileUrl: URL) throws {
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)
        defer {
            fileHandle.closeFile()
        }
        
        if let string = String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8) {
            fileContents = string
        } else {
            throw StreamReaderError.couldNotLoad
        }
        
        lines = fileContents.components(separatedBy: "\n")
    }
    
    init(string: String) {
        fileContents = string
        lines = string.components(separatedBy: "\n")
    }
    
    func readLine() -> String? {
        guard !isEndOfStream else {
            return nil
        }
        defer {
            currentLine += 1
        }
        
        return lines[currentLine]
    }
    
    func readTrimmedLine() -> String? {
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
