//
//  PDUMessageDecoder.swift
//  
//
//  Created by Rafael Warnault, OPALE on 14/07/2021.
//

import Foundation
import NIO

/**
 The `PDUMessageDecoder` is `ByteToMessageDecoder` subclass used by `SwiftNIO` channel pipeline
 to smooth the decoding of received message at the byte level.
 
 What is done here is to read the PDU length of the received message in order to know if we have enougth bytes in the buffer.
 When the PDU length is reached it call `fireChannelRead()` method to pass to completed buffer to the
 next Channel Handler, here it is `DicomAssociation`.
 */
public struct PDUBytesDecoder: ByteToMessageDecoder {
    public typealias InboundOut = PDUMessage
    
    private var association:DicomAssociation!
    private var pduType:[UInt8]?
    private var deadByte:[UInt8]?
    private var length:[UInt8]?
    private var data:[UInt8]?
    private var command:CommandField?
    private var currentMessage:PDUMessage?
    var payload = ByteBuffer()
    
    public init(withAssociation association: DicomAssociation) {
        self.association = association
    }

    public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) -> DecodingState {
        print("decode")
        
        if pduType == nil {
            guard let pt = buffer.readBytes(length: 1) else {
                return .needMoreData
            }

            pduType = pt
        }

        if deadByte == nil {
            guard let db = buffer.readBytes(length: 1) else {
                return .needMoreData
            }

            deadByte = db
        }

        if length == nil {
            guard let l = buffer.readBytes(length: 4) else {
                return .needMoreData
            }

            length = l
        }

        if data == nil {
            let realLength = Int(Data(length!).toInt32(byteOrder: .BigEndian))

            guard let d = buffer.readBytes(length: realLength) else {
                return .needMoreData
            }

            data = d
        }
        
        payload.writeBytes(pduType!)
        payload.writeBytes(deadByte!)
        payload.writeBytes(length!)
        payload.writeBytes(data!)
                
        let pt = PDUType(rawValue: pduType!.first!)!
        var message:PDUMessage? = nil
        
        switch pt {
        case .abort:
            message = Abort(pduType: pt, association: association)
        case .associationRQ:
            message = AssociationRQ(pduType: pt, association: association)
        case .associationAC:
            message = AssociationAC(pduType: pt, association: association)
        case .associationRJ:
            message = AssociationRJ(pduType: pt, association: association)
        case .dataTF:
            message = DataTF(pduType: pt, association: association)
        case .releaseRQ:
            message = ReleaseRQ(pduType: pt, association: association)
        case .releaseRP:
            message = ReleaseRSP(pduType: pt, association: association)
        }
        
        print("read \(message) \(message?.commandField) \(currentMessage)")
                
        let d = Data(payload.readBytes(length: payload.readableBytes)!)
        let status = message?.decodeData(data: d)
        
        print("d \(d.toHex())")
        
        if currentMessage == nil {
            if message?.pduType == .dataTF {
                // ask more data if missing DATA fragment and/or more data fragment are coming
                if let commandField = message?.commandField {
                    print("1. commandField \(commandField)")
                    switch commandField {
                    case .NONE:
                        break
                    case .C_STORE_RQ:
                        break
                    case .C_STORE_RSP:
                        break
                    case .C_GET_RQ:
                        break
                    case .C_GET_RSP:
                        break
                    case .C_FIND_RQ:
                        break
                    case .C_FIND_RSP:
                        if let findRSP = message as? DataTF {
                            if findRSP.resultsDataset == nil {
                                currentMessage = message
                                
                                print("2. Ask for more data")
                                
                                self.clear()
                                
                                return .needMoreData
                                
                            }
                        }
                    case .C_MOVE_RQ:
                        break
                    case .C_MOVE_RSP:
                        break
                    case .C_ECHO_RQ:
                        break
                    case .C_ECHO_RSP:
                        break
                    case .N_EVENT_REPORT_RQ:
                        break
                    case .N_EVENT_REPORT_RSP:
                        break
                    case .N_GET_RQ:
                        break
                    case .N_GET_RSP:
                        break
                    case .N_SET_RQ:
                        break
                    case .N_SET_RSP:
                        break
                    case .N_ACTION_RQ:
                        break
                    case .N_ACTION_RSP:
                        break
                    case .N_CREATE_RQ:
                        break
                    case .N_CREATE_RSP:
                        break
                    case .N_DELETE_RQ:
                        break
                    case .N_DELETE_RSP:
                        break
                    case .C_CANCEL_RQ:
                        break
                    }
                }
            }
        } else {
            print("3. dataTF.receivedData \(message)")
            
            if let dataTF = message as? DataTF {
                if currentMessage?.commandField == .C_FIND_RSP {
                    let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
                    let ts = pc?.transferSyntaxes.first
                    
                    if ts == nil {
                        Logger.error("No transfer syntax found, refused")
                        return .continue
                    }
                    
                    let transferSyntax = TransferSyntax(ts!)
                    
                    print("4. dataTF.receivedData \(dataTF.receivedData)")
                    
                    // last fragment
                    if dataTF.flags == 0x02 {
                        let dis = DicomInputStream(data: dataTF.receivedData)
                        
                        dis.vrMethod    = transferSyntax!.vrMethod
                        dis.byteOrder   = transferSyntax!.byteOrder
                        
                        if let resultsDataset = try? dis.readDataset(enforceVR: false) {
                            print(resultsDataset)
                            currentMessage!.resultsDataset = resultsDataset
                        }
                    }
                }
                
                message = currentMessage
                currentMessage = nil
            }
        }
            
//        let ois = OffsetInputStream(data: d)
//
//        while ois.hasReadableBytes {
//            guard let pvdLength = ois.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
//                Logger.error("Cannot read PDV length")
//                break
//            }
//
//            guard let pdvData = ois.read(length: Int(pvdLength)) else {
//                Logger.error("Cannot read PDV data")
//                break
//            }
//
//            message?.decodePDV(data: pdvData)
//        }
        
        if message != nil {
            context.fireChannelRead(self.wrapInboundOut(message!))
        }

        self.clear()
        
        return .continue
    }
    
    
    mutating func clear() {
        self.payload.clear()
        
        self.pduType     = nil
        self.deadByte    = nil
        self.length      = nil
        self.data        = nil
    }
}
