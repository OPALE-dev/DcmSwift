//
//  DicomFile.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

public class DicomFile {
    // MARK: - Attributes
    
    public var filepath:String!
    public var dataset:DataSet!
    public var acrNema:Bool = false
    
    
    
    
    // MARK: - Public methods

    public init?(forPath filepath: String) {
        initLogger()
        
        if !FileManager.default.fileExists(atPath: filepath) {
            SwiftyBeaver.error("No such file at \(filepath)")
            return nil
        }
        
        if !DicomFile.isDicomFile(filepath) {
            SwiftyBeaver.error("Not a DICOM file at \(filepath)")
            return nil
        }
        
        self.filepath   = filepath
        
        if !self.load() {
            return nil
        }
    }
    

    
    public func fileSizeWithUnit() -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(self.fileSize()), countStyle: .file)
    }
    
    
    
    public func fileSize() -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: self.filepath)
            return attr[FileAttributeKey.size] as! UInt64
        } catch {
            SwiftyBeaver.error("Error: \(error)")
            return 0
        }
    }
    
    
    public func fileName() -> String {
        return (self.filepath as NSString).lastPathComponent
    }
    
    
    public func write(atPath path:String, vrMethod inVrMethod:DicomSpec.VRMethod? = nil, byteOrder inByteOrder:DicomSpec.ByteOrder? = nil) -> Bool {
        return self.dataset.write(atPath:path, vrMethod:inVrMethod, byteOrder:inByteOrder)
    }
    
    
    
    // MARK: - Static methods
    
    /**
     A static helper to check if the given file is a DICOM file
     - Returns: A boolean value that indicates if the file is readable by DcmSwift
     */
    public static func isDicomFile(_ filepath: String) -> Bool {
        let url = URL.init(fileURLWithPath: filepath)
        var data:Data
        
        initLogger()
        
        do {
            try data = Data(contentsOf: url)
            if data.count <= 128 {
                SwiftyBeaver.error("Not enought data in preamble, not a valid DICOM file.")
            }
            
            let range:Range<Data.Index> = 128..<132
            let subdata:Data            = data.subdata(in: range)
            let magic:String            = subdata.toString()
            
            if magic == "DICM" {
                return true
            } else {
                // maybe try to catch ACR-NEMA 2.0 file header
                let range:Range<Data.Index> = 0..<8
                let subdata:Data = data.subdata(in: range)
                // ACR-NEMA 2.0 magic bytes ?
                if subdata == Data([0x08, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00]) {
                    return true
                }
                
                SwiftyBeaver.error("DICM magic word not found, not a valid DICOM file. ")
            }
        } catch {
            SwiftyBeaver.error("Enable to load file data, not a valid DICOM file.")
            return false
        }
        return false
    }
    
    
    
    
    // MARK: - Private methods
    
    private func load() -> Bool {
        let url = URL.init(fileURLWithPath: self.filepath)
 
        SwiftyBeaver.info("* Load file : \(self.fileName())")
        SwiftyBeaver.debug("  -> File path : \(self.filepath ?? "")")
        SwiftyBeaver.debug("  -> File size : \(self.fileSizeWithUnit())")
        
        do {
            let data:Data   = try Data(contentsOf: url)
            
            // check wheather or not the header exists
            if data.count <= 128 {
                SwiftyBeaver.error("Not enought data in preamble, not a valid DICOM file.")
                return false
            }
            
            // check for DICOM file with header
            let range:Range<Data.Index> = 128..<132
            let subdata:Data            = data.subdata(in: range)
            let magic:String            = subdata.toString()
            
            if magic != "DICM" {
                SwiftyBeaver.error("DICM magic word not found. Try without meta-header (ACR-NEMA 2.0)")
                
                // maybe try to catch ACR-NEMA 2.0 file header
                let range:Range<Data.Index> = 0..<8
                let subdata:Data = data.subdata(in: range)
                self.acrNema = true
                
                // ACR-NEMA 2.0 magic bytes ?
                if subdata != Data([0x08, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00]) {
                    SwiftyBeaver.error("Enable to read the file header, abort!")
                    return false
                }
            }
            
            SwiftyBeaver.debug("  -> Meta-Information Header : \(!self.acrNema)")
            
            // read dataset and load data
            self.dataset = DataSet(withData: data, readHeader: !self.acrNema)
            let rez = self.dataset.loadData()
            
            SwiftyBeaver.debug("  -> Transfer Syntax : \(self.dataset.transferSyntax)")
            SwiftyBeaver.debug("  -> Byte Order : \(self.dataset.byteOrder)")
            
            if !rez {
               SwiftyBeaver.error("Enable to load file dataset, abort!")
            }
            
            return rez
        } catch {
            SwiftyBeaver.error("Enable to load file data, abort!")
            return false
        }
    }
}
