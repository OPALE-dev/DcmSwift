//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 12/07/2021.
//

import Foundation

public class OffsetInputStream {
    var stream:InputStream!
    
    /// A copy of the original stream used if we need to reset the read offset
    var backstream:InputStream!
    
    /// The current position of the cursor in the stream
    internal var offset = 0
    
    /// The total number of bytes in the stream
    internal var total  = 0
    
    public var hasReadableBytes:Bool {
        get {
            return offset < total
        }
    }
    
    public var readableBytes:Int {
        get {
            return total - offset
        }
    }
    
    /**
     Init a DicomInputStream with a file path
     */
    public init(filePath:String) {
        stream      = InputStream(fileAtPath: filePath)
        backstream  = InputStream(fileAtPath: filePath)
        total       = Int(DicomFile.fileSize(path: filePath))
    }
    
    /**
    Init a DicomInputStream with a file URL
    */
    public init(url:URL) {
        stream      = InputStream(url: url)
        backstream  = InputStream(url: url)
        total       = Int(DicomFile.fileSize(path: url.path))
    }
    
    /**
    Init a DicomInputStream with a Data object
    */
    public init(data:Data) {
        stream      = InputStream(data: data)
        backstream  = InputStream(data: data)
        total       = data.count
    }
    
    
    deinit {
        close()
    }
    
    /**
     Opens the stream
     */
    public func open() {
        stream.open()
        backstream.open()
    }
    
    /**
     Closes the stream
     */
    public func close() {
        stream.close()
        backstream.close()
    }

    
    /**
     Reads `length` bytes and returns the data read from the stream
     
     - Parameter length: the number of bytes to read
     - Returns: the data read in the stream, or nil
     */
    public func read(length:Int) -> Data? {
        guard length >= 0, length <= readableBytes else { return nil }
        if length == 0 { return Data() }

        var data = Data(count: length)
        var bytesRead = 0
        let succeeded = data.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }
            while bytesRead < length {
                let result = stream.read(baseAddress.advanced(by: bytesRead), maxLength: length - bytesRead)
                guard result > 0 else { return false }
                bytesRead += result
            }
            return true
        }

        guard succeeded else {
            offset += bytesRead
            return nil
        }
        offset += bytesRead
        return data
    }

    
    /**
     Jumps of `bytes` bytes  in the stream
     
     - Parameter bytes: the number of bytes to jump in the stream
     */
    internal func forward(by bytes: Int) {
        // read into the void...
        _ = read(length: bytes)
    }
}
