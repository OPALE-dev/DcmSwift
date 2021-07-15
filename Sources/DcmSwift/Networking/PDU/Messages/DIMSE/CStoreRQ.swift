//
//  CStoreRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CStoreRQ` class represents a C-STORE-RQ message of the DICOM standard.
 
 Its main property is a `DicomFile` object, the one that will be transfered over the DIMSE service.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part07/sect_9.3.html
 */
public class CStoreRQ: DataTF {
    public var dicomFile:DicomFile?
    
    public override func messageName() -> String {
        return "C-STORE-RQ"
    }
    
    
    public override func data() -> Data {
        var data = Data()
        
        // get file SOPClassUID
        if let sopClassUID    = dicomFile?.dataset.string(forTag: "SOPClassUID"),
           let sopInstanceUID = dicomFile?.dataset.string(forTag: "SOPInstanceUID") {
            // find context ID in accepted presentation context
            let pcs:[PresentationContext] = self.association.acceptedPresentationContexts(forSOPClassUID: sopClassUID)
            
            if !pcs.isEmpty {
                let commandDataset = DataSet()
                _ = commandDataset.set(value: CommandField.C_STORE_RQ.rawValue.bigEndian, forTagName: "CommandField")
                _ = commandDataset.set(value: sopClassUID, forTagName: "AffectedSOPClassUID")
                _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
                _ = commandDataset.set(value: UInt16(0).bigEndian, forTagName: "Priority")
                _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "CommandDataSetType")
                _ = commandDataset.set(value: sopInstanceUID, forTagName: "AffectedSOPInstanceUID")
                
                Logger.debug("Waaaaaaaaaa")
                Logger.debug(self.association.acceptedTransferSyntax ?? "")
                
                var vrMethod: VRMethod = .Explicit
                var byteOrder: ByteOrder  = .LittleEndian

                
                if let transferSyntax = self.association.acceptedTransferSyntax {
                    Logger.debug("LALALILALALALA")
                    let tsName  = DicomSpec.shared.nameForUID(withUID: transferSyntax)
                    
                    if tsName == TransferSyntax.implicitVRLittleEndian {
                        vrMethod    = .Implicit
                        byteOrder   = .LittleEndian
                    } else if tsName == TransferSyntax.explicitVRBigEndian {
                        vrMethod    = .Explicit
                        byteOrder   = .BigEndian
                    } else if tsName == TransferSyntax.explicitVRLittleEndian {
                        vrMethod    = .Explicit
                        byteOrder   = .LittleEndian
                    }
                    
                } else {
                    Logger.debug("Booooooooooon")
                    vrMethod    = .Explicit
                    byteOrder   = .LittleEndian
                    // TODO warning
                    // Little endian explicit
                }
                
                
                let commandGroupLength = commandDataset.toData(vrMethod: vrMethod, byteOrder: byteOrder).count
                _ = commandDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")
                
                var pdvData = Data()
                let pdvLength = commandGroupLength + 14
                pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
                pdvData.append(uint8: pcs.first!.contextID, bigEndian: true) // Context
                pdvData.append(byte: 0x03) // Flags
                pdvData.append(commandDataset.toData(vrMethod: vrMethod, byteOrder: byteOrder))
                                                
                let pduLength = UInt32(pdvLength + 4)
                data.append(uint8: self.pduType.rawValue, bigEndian: true)
                data.append(byte: 0x00) // reserved
                data.append(uint32: pduLength, bigEndian: true)
                data.append(pdvData)
            }
        }
        else {
            print("No SOPClassUID found, file not sent.")
        }
        
        return data
    }
    
    
    
    public override func messagesData() -> [Data] {
        var datas:[Data] = []
        
        if let sopClassUID = dicomFile?.dataset.string(forTag: "SOPClassUID") {
            let pcs:[PresentationContext] = self.association.acceptedPresentationContexts(forSOPClassUID: sopClassUID)
            
            if !pcs.isEmpty {
                if let dataset = dicomFile?.dataset {
                    let fileData = dataset.DIMSEData()
                    
                    let chunks = fileData.chunck(into: 16372)
                    var index = 0
                    
                    for chunkData in chunks {
                        var data = Data()
                        var pdvData2 = Data()
                        let pdvLength2 = chunkData.count + 2
                        
                        pdvData2.append(uint32: UInt32(pdvLength2), bigEndian: true)
                        pdvData2.append(uint8: pcs.first!.contextID, bigEndian: true) // Context
                        
                        if chunkData == chunks.last {
                            pdvData2.append(byte: 0x02) // Flags : last fragment
                        } else {
                            pdvData2.append(byte: 0x00) // Flags : more fragment coming
                        }
                        pdvData2.append(chunkData)
                        
                        let pduLength2 = UInt32(pdvLength2 + 4)
                        data.append(uint8: self.pduType.rawValue, bigEndian: true)
                        data.append(byte: 0x00) // reserved
                        data.append(uint32: pduLength2, bigEndian: true)
                        data.append(pdvData2)
                        
                        datas.append(data)
                        index += 1
                    }
                }
            }
        }
        
        return datas
    }
    
    public override func handleResponse(data: Data) -> PDUMessage? {
//        if let command:UInt8 = data.first {
//            if command == self.pduType.rawValue {
//                if let message = PDUDecoder.shared.receiveDIMSEMessage(data: data, pduType: PDUType.dataTF, commandField: CommandField.C_STORE_RSP, association: self.association) as? PDUMessage {
//                    return message
//                }
//            }
//        }
        return nil
    }
}
