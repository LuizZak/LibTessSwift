//
//  DDFileReader.swift
//  LogParser
//
//  Created by Luiz Fernando Silva on 10/01/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

import Foundation

public extension Data {
    func rangeOfData_dd(_ dataToFind: Data) -> Range<Data.Index>? {
        return self.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Range<Data.Index>? in
            dataToFind.withUnsafeBytes { (searchBytes: UnsafePointer<UInt8>) -> Range<Data.Index>? in
                let length = self.count
                let searchLength: Data.Index = dataToFind.count
                var searchIndex: Data.Index = 0
                
                var start: Data.Index = -1
                
                for index in 0..<length {
                    if(bytes[index] == searchBytes[searchIndex]) {
                        //the current character matches
                        if (start == -1) {
                            start = index
                        }
                        searchIndex += 1
                        
                        if (searchIndex >= searchLength) {
                            return start..<(start+searchLength)
                        }
                    } else {
                        searchIndex = 0
                        start = -1
                    }
                }
                
                return nil
            }
        }
    }
}

public protocol StreamLineReader {
    var isEndOfStream: Bool { get }
    
    var dataConsumed: UInt64 { get }
    
    func readLine() -> String?
}

public protocol StreamLineReaderPeekable: StreamLineReader {
    func peekLine() -> String?
}

public class DDStreamReader: StreamLineReaderPeekable {
    var closeOnDealloc = false
    
    var chunkSize: Int
    
    private var bufferedReader: BufferedStreamReader
    
    /// Total ammount of data consumed from the steram by this reader so far.
    /// This includes only data that was returned so far from readLine(), not
    /// the total bytes read from the underlying stream so far
    final fileprivate(set) public var dataConsumed: UInt64 = 0
    
    fileprivate var lineDelimiterData: Data
    fileprivate var delimiterLength: Int
    
    var lineDelimiter: String = "\n" {
        didSet {
            lineDelimiterData = lineDelimiter.data(using: .utf8)!
            delimiterLength = lineDelimiterData.count
        }
    }
    
    public var isEndOfStream: Bool {
        return !bufferedReader.hasBytesAvailable
    }
    
    init(inputStream: InputStream, closeOnDealloc: Bool = true) {
        self.bufferedReader = BufferedStreamReader(stream: inputStream)
        self.closeOnDealloc = closeOnDealloc
        
        self.lineDelimiter = "\n"
        self.lineDelimiterData = self.lineDelimiter.data(using: .utf8)!
        self.delimiterLength = self.lineDelimiterData.count
        chunkSize = 512
    }
    
    deinit {
        if(closeOnDealloc) {
            bufferedReader.stream.close()
        }
    }
    
    /// Reads and returns a line from the stream, buffering the result, without 
    /// modifying the current head position.
    ///
    /// This modifies the position from the stream to buffer the data, but the
    /// underlying buffer is reset to the previous position before the reading
    /// operation.
    ///
    /// Returns nil, if no data is available from the stream
    final public func peekLine() -> String? {
        if (!bufferedReader.hasBytesAvailable) {
            return nil
        }
        
        var shouldReadMore = true
        var currentData = Data()
        
        let beforeRead = bufferedReader.bufferOffset
        
        autoreleasepool { () -> Void in
            while (shouldReadMore) {
                if (!bufferedReader.hasBytesAvailable) {
                    break
                }
                
                var chunk = bufferedReader.read(count: chunkSize)
                
                if let newLineRange = chunk.rangeOfData_dd(lineDelimiterData) {
                    // include the length so we can include the delimiter in the
                    // string
                    let range: Range<Data.Index> = 0..<(newLineRange.upperBound-1+delimiterLength)
                    chunk = chunk.subdata(in: range)
                    // Rewind buffer to previous state
                    bufferedReader.setOffset(beforeRead)
                    
                    shouldReadMore = false
                }
                currentData.append(chunk)
            }
        }
        
        return String(data: currentData, encoding: .utf8)
    }
    
    /// Reads a line from the stream.
    /// Returns nil, if no data is available from the stream
    final public func readLine() -> String? {
        if (!bufferedReader.hasBytesAvailable) {
            return nil
        }
        
        var shouldReadMore = true
        var currentData = Data()
        
        autoreleasepool { () -> Void in
            while (shouldReadMore) {
                if (!bufferedReader.hasBytesAvailable) {
                    break
                }
                
                var chunk = bufferedReader.read(count: chunkSize)
                
                if let newLineRange = chunk.rangeOfData_dd(lineDelimiterData) {
                    // include the length so we can include the delimiter in the
                    // string
                    let range: Range<Data.Index> = 0..<(newLineRange.upperBound-1+delimiterLength)
                    let before = chunk.count
                    chunk = chunk.subdata(in: range)
                    // Rewind buffer
                    bufferedReader.rewindBuffer(by: before - chunk.count)
                    bufferedReader.trimBuffer()
                    
                    shouldReadMore = false
                }
                currentData.append(chunk)
                dataConsumed += UInt64(chunk.count)
            }
        }
        
        return String(data: currentData, encoding: .utf8)
    }
    
    final func readTrimmedLine() -> String? {
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Provides a wrapper over an input stream that allows buffered data
    /// reading while mantaining a backtrackable buffer that can be rewinded to
    /// a previous relative position that is still buffered
    private class BufferedStreamReader {
        
        var stream: InputStream
        var buffer: Data = Data()
        var bufferOffset = 0
        var hardStop = false
        
        var hasBytesAvailable: Bool {
            // If at end of stream bytes, return whether we have bytes left in
            // buffer
            if(hardStop || !stream.hasBytesAvailable) {
                return bufferOffset < buffer.count
            }
            
            return true
        }
        
        init(stream: InputStream) {
            self.stream = stream
        }
        
        func fillBuffer(length: Int) -> Int {
            var target = Data(count: length)
            let read = target.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Int in
                stream.read(bytes, maxLength: length)
            }
            if(read < length) {
                hardStop = true
            }
            buffer.append(target.subdata(in: 0..<read))
            
            return read
        }
        
        func read(count: Int) -> Data {
            var read = count
            if(buffer.count < count + bufferOffset) {
                // Empty data object
                if(hardStop || !stream.hasBytesAvailable) {
                    if(bufferOffset < buffer.count) {
                        read = buffer.count - bufferOffset
                    } else {
                        return Data()
                    }
                } else {
                    // Fill buffer with required ammount
                    read = fillBuffer(length: count)
                }
            }
            
            defer {
                bufferOffset += read
            }
            
            return buffer.subdata(in: bufferOffset..<bufferOffset+read)
        }
        
        func rewindBuffer(by count: Data.Index) {
            bufferOffset = max(0, bufferOffset - count)
        }
        
        func setOffset(_ offset: Int) {
            bufferOffset = 0
        }
        
        /// Trims the buffer, removing any data prior to the bufferOffset point,
        /// and resets the buffer offset back to 0
        func trimBuffer() {
            if(buffer.count != 0) {
                buffer = buffer.subdata(in: bufferOffset..<buffer.count)
            }
            
            bufferOffset = 0
        }
    }
}

/// A stream reader fit to read from a file URL
class DDFileReader: DDStreamReader {
    
    let fileUrl: URL
    
    init(fileUrl: URL) throws {
        guard let stream = InputStream(url: fileUrl) else {
            throw FileReaderError.invalidFileUrl
        }
        
        stream.open()
        
        self.fileUrl = fileUrl
        
        super.init(inputStream: stream, closeOnDealloc: true)
    }
    
    static func getFileLength(atUrl url: URL) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            handle.closeFile()
        }
        return handle.seekToEndOfFile()
    }
    
    enum FileReaderError: Error {
        case invalidFileUrl
    }
}

/// File reader fit for reading from files with a high capacity output
final class DDUnbufferedFileReader: StreamLineReader {
    
    var fileUrl: URL
    
    var fileHandle: FileHandle
    
    var chunkSize: Int
    
    fileprivate var lineDelimiterData: Data
    fileprivate var delimiterLength: Int
    
    var currentOffset: UInt64
    var totalFileLength: UInt64
    
    var dataConsumed: UInt64 {
        return currentOffset
    }
    
    var lineDelimiter: String = "\n" {
        didSet {
            lineDelimiterData = lineDelimiter.data(using: .utf8)!
            delimiterLength = lineDelimiterData.count
        }
    }
    
    var isEndOfStream: Bool {
        return currentOffset < totalFileLength
    }
    
    init(fileUrl: URL) throws {
        self.fileUrl = fileUrl
        fileHandle = try FileHandle(forReadingFrom: fileUrl)
        
        self.lineDelimiter = "\n"
        self.lineDelimiterData = self.lineDelimiter.data(using: .utf8)!
        self.delimiterLength = self.lineDelimiterData.count
        self.currentOffset = 0
        chunkSize = 512
        totalFileLength = fileHandle.seekToEndOfFile()
        //we don't need to seek back, since readLine will do that.
    }
    
    deinit {
        fileHandle.closeFile()
    }
    
    func readLine() -> String? {
        if (currentOffset >= self.totalFileLength) {
            return nil
        }
        
        fileHandle.seek(toFileOffset: currentOffset)
        
        var currentData = Data()
        var shouldReadMore = true
        
        autoreleasepool { () -> Void in
            while (shouldReadMore) {
                if (currentOffset >= totalFileLength) {
                    break
                }
                
                var chunk = fileHandle.readData(ofLength: chunkSize)
                
                if let newLineRange = chunk.rangeOfData_dd(lineDelimiterData) {
                    // include the length so we can include the delimiter in the
                    // string
                    let range: Range<Data.Index> = 0..<(newLineRange.upperBound-1+delimiterLength)
                    chunk = chunk.subdata(in: range)
                    
                    shouldReadMore = false
                }
                currentData.append(chunk)
                currentOffset += UInt64(chunk.count)
            }
        }
        
        return String(data: currentData, encoding: .utf8)
    }
    
    func readTrimmedLine() -> String? {
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

