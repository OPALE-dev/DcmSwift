//
//  DicomFile.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation

public class DicomFile {
    public var filepath:String!
    public var dataset:DataSet!
    
    
    public init?(forPath filepath: String) {
        if !FileManager.default.fileExists(atPath: filepath) {
            print("No such file at \(filepath)")
            return nil
        }
        
        if !DicomFile.isDicomFile(filepath) {
            print("Not a DICOM file at \(filepath)")
            return nil
        }
        
        self.filepath   = filepath
        
        if !self.load() {
            return nil
        }
    }
    
    
    

    public static func isDicomFile(_ filepath: String) -> Bool {
        let url = URL.init(fileURLWithPath: filepath)
        var data:Data
        
        do {
            try data = Data(contentsOf: url)
            if data.count <= 128 {
                print("Not enought data in preamble, not a valid DICOM file.")
            }
            
            let range:Range<Data.Index> = 128..<132
            let subdata:Data            = data.subdata(in: range)
            let magic:String            = subdata.toString()
            
            if magic == "DICM" {
                return true
            } else {
                print("DICM magic word not found, not a valid DICOM file. ")
            }
        } catch {
            print("Enable to load file data, not a valid DICOM file.")
            return false
        }
        return false
    }
    
    
    
    
    public func fileSizeWithUnit() -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(self.fileSize()), countStyle: .file)
    }
    
    
    
    public func fileSize() -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: self.filepath)
            return attr[FileAttributeKey.size] as! UInt64
        } catch {
            print("Error: \(error)")
            return 0
        }
    }
    
    public func write(atPath path:String) -> Bool {
        return self.dataset.write(atPath: path)
    }
    
    
    
    
    // MARK: Private methods
    private func load() -> Bool {
        let url = URL.init(fileURLWithPath: self.filepath)
 
        do {
            let data:Data   = try Data(contentsOf: url)
            self.dataset    = DataSet(withData: data)
            
            if self.dataset.loadData() {
                return true
            }
        } catch {
            print("Enable to load file data, abort!")
            return false
        }
        
        return false
    }
}
