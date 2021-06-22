//
//  DicomFile.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

/**
 Class representing a DICOM file and all associated methods.
 With this class you can load a DICOM file from a given path to access its dataset of attributes.
 You can also write the dataset back to a file, process some validation, and get access to image or PDF data.
 */
public class DicomFile {
    // MARK: - Attributes
    /// The path of the loaded DICOM file
    public var filepath:String!
    /// The parsed dataset containing all the DICOM attributes
    public var dataset:DataSet!
    /// Define if the file has a standard DICOM prefix header. If yes, parsing witll start at 132 bytes offset, else at 0.
    public var hasPreamble:Bool = true
    /// A flag that informs if the file is a DICOM encapsulated PDF
    public var isEncapsulatedPDF = false
    
    
    
    // MARK: - Public methods
    /**
    Load a DICOM file
     
    - Parameter filepath: the path of the DICOM file to load
    */
    public init?(forPath filepath: String) {
        if !FileManager.default.fileExists(atPath: filepath) {
            Logger.error("No such file at \(filepath)")
            return nil
        }
        
        self.filepath = filepath
        
        if !self.read() { return nil }
    }
    

    /**
    Get the formatted size of the current file path
     
    - Returns: a formatted string of the size in bytes of the current file path
    */
    public func fileSizeWithUnit() -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(self.fileSize()), countStyle: .file)
    }
    
    
    /**
    Get the size of the current file path
     
    - Returns: the size in bytes of the current file path
    */
    public func fileSize() -> UInt64 {
        return DicomFile.fileSize(path: self.filepath)
    }
    
    public class func fileSize(path:String) -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: path)
            return attr[FileAttributeKey.size] as! UInt64
        } catch {
            Logger.error("Error: \(error)")
            return 0
        }
    }
    
    /**
    Get the filename of the current file path
     
    - Returns: the filename (with extension) of the current file path
    */
    public func fileName() -> String {
        return (self.filepath as NSString).lastPathComponent
    }
    
    /**
     Write the DICOM file at given path.
     
     - Parameter path: Path where to write the file
     - Parameter inVrMethod: the VR method used to write the file (explicit vs. implicit)
     - Parameter byteOrder: the endianess used to write the file (big vs. little endian)
     
     - Returns: true if the file was successfully written
     */
    public func write(
        atPath path:String,
        vrMethod inVrMethod:DicomConstants.VRMethod? = nil,
        byteOrder inByteOrder:DicomConstants.ByteOrder? = nil
    ) -> Bool {
        return self.dataset.write(atPath:path, vrMethod:inVrMethod, byteOrder:inByteOrder)
    }
    
    /**
     Write the DICOM file at given path.
     
     - Parameter path: Path where to write the file
     - Parameter transferSyntax: The transfer syntax used to write the file (EXPERIMENTAL)
     
     - Returns: true if the file was successfully written
     */
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
    
    
    /**
    - Returns: true if the file was found corrupted while parsing.
    */
    public func isCorrupted() -> Bool {
        return self.dataset.isCorrupted
    }
    
    
    /**
    Validate the file against DICM embedded specification (DcmSpec)
     
     - Returns: A ValidationResult array containing errors and warning issued from the validation process
    */
    public func validate() -> [ValidationResult] {
        return DicomSpec.shared.validate(file: self)
    }
    
    
    /**
     An instane of DicomImage if available.
     */
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

    
    // MARK: - Static methods
    
    /**
     A static helper to check if the given file is a DICOM file
     
     It first looks at `DICM` magic world, and if not found (for old ACR-NEMA type of files) it
     checks the first group,element pair (0008,0004) before accepting the file as DICOM or not
     
     - Returns: A boolean value that indicates if the file is readable by DcmSwift
     */
    public static func isDicomFile(_ filepath: String) -> Bool {
        let inputStream = DicomInputStream(filePath: filepath)
        
        do {
            _ = try inputStream.readDataset(withoutPixelData: true)
            
            return true
        } catch _ {
            return false
        }
    }
}

// MARK: - Private DicomFile methods
extension DicomFile {
    private func read() -> Bool {
        let inputStream = DicomInputStream(filePath: filepath)
        
        do {
            if let dataset = try inputStream.readDataset() {
                hasPreamble     = inputStream.hasPreamble
                self.dataset    = dataset
                
                if let s = self.dataset.string(forTag: "MIMETypeOfEncapsulatedDocument") {
                    if s.trimmingCharacters(in: .whitespaces) == "application/pdf " {
                        Logger.debug("  -> MIMETypeOfEncapsulatedDocument : application/pdf")
                        isEncapsulatedPDF = true
                    }
                }
                
                return true
            }
        } catch DicomInputStream.StreamError.cannotOpenStream {
            Logger.error("Cannot open stream to path: \(String(describing: filepath))")
        } catch DicomInputStream.StreamError.cannotReadStream {
            Logger.error("Cannot read stream to path: \(String(describing: filepath))")
        } catch DicomInputStream.StreamError.notDicomFile {
            Logger.error("Not a DICOM file at path: \(String(describing: filepath))")
        } catch DicomInputStream.StreamError.datasetIsCorrupted {
            Logger.error("Dataset is corrupted: \(String(describing: filepath))")
        } catch {
            Logger.error("Unknow error while reading: \(String(describing: filepath))")
        }
                
        return false
    }
}
