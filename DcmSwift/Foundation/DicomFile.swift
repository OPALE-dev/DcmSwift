//
//  DicomFile.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


public class DicomFile {
    // MARK: - Attributes
    
    public var filepath:String!
    public var dataset:DataSet!
    public var hasPrefixHeader:Bool = true
    public var isEncapsulatedPDF = false
    
    
    
    // MARK: - Public methods
    public init?(forPath filepath: String) {
        if !FileManager.default.fileExists(atPath: filepath) {
            Logger.error("No such file at \(filepath)")
            return nil
        }
        
        if !DicomFile.isDicomFile(filepath) {
            Logger.error("Not a DICOM file at \(filepath)")
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
            Logger.error("Error: \(error)")
            return 0
        }
    }
    
    
    public func fileName() -> String {
        return (self.filepath as NSString).lastPathComponent
    }
    
    
    public func write(atPath path:String, vrMethod inVrMethod:DicomConstants.VRMethod? = nil, byteOrder inByteOrder:DicomConstants.ByteOrder? = nil) -> Bool {
        return self.dataset.write(atPath:path, vrMethod:inVrMethod, byteOrder:inByteOrder)
    }
    
    
    public func write(atPath path:String, transferSyntax:String) -> Bool {
        if transferSyntax == DicomConstants.explicitVRLittleEndian {
            return self.dataset.write(atPath:path, vrMethod: .Explicit, byteOrder: .LittleEndian)
        }
        else if transferSyntax == DicomConstants.implicitVRLittleEndian {
            return self.dataset.write(atPath:path, vrMethod: .Implicit, byteOrder: .LittleEndian)
        }
        else if transferSyntax == DicomConstants.explicitVRBigEndian {
            return self.dataset.write(atPath:path, vrMethod: .Explicit, byteOrder: .BigEndian)
        }
        return false
    }
    
    
    
    public func isCorrupted() -> Bool {
        return self.dataset.isCorrupted
    }
    
    
    
    public func validate() -> [ValidationResult] {
        return DicomSpec.shared.validate(file: self)
    }
    
    
    
    public var dicomImage: DicomImage? {
        get {
            return DicomImage(self.dataset)
        }
    }
    
    
    public func pdfData() -> Data? {
        if self.isEncapsulatedPDF {
            if let e = self.dataset.element(forTagName: "EncapsulatedDocument") {
                if e.length > 0 && e.data != nil {
                    return e.data
                }
            }
        }
        return nil
    }
    
    public var encapsulatedPDF:Data? {
        get {
            return Data()
        }
    }
    
    
    // MARK: - Static methods
    
    /**
     A static helper to check if the given file is a DICOM file
     - Returns: A boolean value that indicates if the file is readable by DcmSwift
     */
    public static func isDicomFile(_ filepath: String) -> Bool {
        let url = URL.init(fileURLWithPath: filepath)
        var data:Data
        
        
        
        do {
            try data = Data(contentsOf: url)
                        
            if data.count <= 128 {
                Logger.error("Not enought data in preamble, not a valid DICOM file, not a reagular DICOM file.")
            }
            
            let range:Range<Data.Index> = 128..<132
            let subdata:Data            = data.subdata(in: range)
            let magic:String            = subdata.toString()
            
            if magic == "DICM" {
                return true
            } else {
                /// maybe try to catch ACR-NEMA file header
                let range:Range<Data.Index> = 0..<8
                let subdata:Data = data.subdata(in: range)
                // ACR-NEMA lol magic bytes ?
                if subdata == Data([0x08, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00]) {
                    return true
                }
                
                Logger.error("DICM magic word not found, not a reagular DICOM file. Try to read Dataset anyway.")
            }
        } catch {
            Logger.error("Enable to load file dataset, not a valid DICOM file: \(error)")
            return false
        }
        return false
    }
    
    
    
    
    // MARK: - Private methods
    
    private func load() -> Bool {
        let url = URL.init(fileURLWithPath: self.filepath)
 
        Logger.info("* Load file : \(self.fileName())")
        Logger.debug("  -> File path : \(self.filepath ?? "")")
        Logger.debug("  -> File size : \(self.fileSizeWithUnit())")
        
        do {
            let data:Data   = try Data(contentsOf: url)
            
            // check wheather or not the header exists
            if data.count <= 8 {
                Logger.error("Not enought data in preamble, not a valid DICOM file.")
                return false
            }
            
            // check for DICOM file with header
            let range:Range<Data.Index> = 128..<132
            let subdata:Data            = data.subdata(in: range)
            let magic:String            = subdata.toString()
            
            if magic != "DICM" {
                Logger.error("DICM magic word not found. Try without prefix-header (ACR-NEMA)")
                
                // maybe try to catch no prefix header file (ACR-NEMA)
                let range:Range<Data.Index> = 0..<8
                let subdata:Data = data.subdata(in: range)
                
                // ultimate check for truncated DICOM file (ACR-NEMA magic bytes ?!)
                if subdata != Data([0x08, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00]) {
                    Logger.error("Enable to read the file header, abort!")
                    return false
                }
                
                self.hasPrefixHeader = false
            }
            
            Logger.debug("  -> Meta-Information Header : \(!self.hasPrefixHeader)")
            
            // read dataset and load data
            self.dataset = DataSet(withData: data, readHeader: self.hasPrefixHeader)
            let rez = self.dataset.loadData()
            
            Logger.debug("  -> Transfer Syntax : \(self.dataset.transferSyntax)")
            Logger.debug("  -> Byte Order : \(self.dataset.byteOrder)")
            
            if !rez {
               Logger.error("Enable to load file dataset, abort!")
            }
            
            if let s = self.dataset.string(forTag: "MIMETypeOfEncapsulatedDocument") {
                if s.trimmingCharacters(in: .whitespaces) == "application/pdf " {
                    Logger.debug("  -> MIMETypeOfEncapsulatedDocument : application/pdf")
                    self.isEncapsulatedPDF = true
                }
            }
            
            return rez
        } catch {
            Logger.error("Enable to load file data, abort!")
            return false
        }
    }
}
