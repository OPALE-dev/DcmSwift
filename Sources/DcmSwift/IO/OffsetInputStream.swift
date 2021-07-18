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
    
    internal var offset = 0
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
    
    
    public func open() {
        stream.open()
        backstream.open()
    }
    
    
    public func close() {
        stream.close()
        backstream.close()
    }

    
    
    public func read(length:Int) -> Data? {
        // allocate memory buffer with given length
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        
        // fill the buffer by reading bytes with given length
        let read = stream.read(buffer, maxLength: length)
        
        if read < 0 || read < length {
            //Logger.warning("Cannot read \(length) bytes")
            return nil
        }
        
        // create a Data object with filled buffer
        let data = Data(bytes: buffer, count: length)
        
        // maintain local offset
        offset += read
        
        // clean the memory
        buffer.deallocate()
        
        return data
    }

    
    
    internal func forward(by bytes: Int) {
        // read into the void...
        _ = read(length: bytes)
    }
}
