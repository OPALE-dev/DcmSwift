//
//  File.swift
//  
//
//  Created by Rafael Warnault on 16/07/2021.
//

import Foundation

// try? PDUStateMachine.shared.handle(event: .AE1(assoc: self))

internal class PDUStateMachine {
    typealias Transition = () throws -> (PDUState)
    
    var state = PDUState.Sta1 // initial state
    
    
    enum PDUState {
        case  Sta1
        case  Sta2
        case  Sta3
        case  Sta4
        case  Sta5
        case  Sta6
        case  Sta7
        case  Sta8
        case  Sta9
        case Sta10
        case Sta11
        case Sta12
        case Sta13
    }


    enum PDUAction {
        case AE1(assoc: DicomAssociation)
        case AE2(assoc: DicomAssociation)
        case AE3(assoc: DicomAssociation)
        case AE4
        case AE5
        case AE6(assoc: DicomAssociation)
        case AE7
        case AE8
        
        case DT1
        case DT2
        
        case AR1
        case AR2
        case AR3
        case AR4
        case AR5
        case AR6
        case AR7
        case AR8
        case AR9
        case AR10
        
        case AA1
        case AA2
        case AA3
        case AA4
        case AA5
        case AA6
        case AA7
        case AA8
    }
    
    
    enum StateErrors: Error {
        case transitionNotFound
    }
    
    
    func transition(forEvent event: PDUAction) throws -> Transition {
        switch (state, event) {
            case (.Sta1, .AE1(let assoc)): return AE1(assoc: assoc)
            case (.Sta3, .AE1(let assoc)): return AA8(assoc: assoc)
            case (.Sta4, .AE2(let assoc)): return AE2(assoc: assoc)
            case (.Sta5, .AE3(let assoc)): return AE3(assoc: assoc)
            case (.Sta6, .AE6(let assoc)): return AE6(assoc: assoc)
            default: throw StateErrors.transitionNotFound
        }
    }
    
    
    func handle(event: PDUAction) throws {
        let t = try transition(forEvent: event)
        
        state = try t()
    }
    
    
    func AE1(assoc: DicomAssociation) -> Transition {
        return {
            // Try to connect
            Logger.info("CONNECTING...")
            
            // Issue TRANSPORT CONNECT request primitive to local transport serviceNext state is Sta4

            // Return the new state
            return .Sta4
        }
    }

    
    func AE2(assoc: DicomAssociation) -> Transition {
        return {
            // connection confirmed
            Logger.info("CONNECTED!, Send A-ASSOCIATE-RQ")
            
            // Send A-ASSOCIATE-RQ-PDU Next state is Sta5

            // Return the new state
            return .Sta5
        }
    }
    
    
    func AE3(assoc: DicomAssociation) -> Transition {
        return {
            // Association confirmed
            Logger.info("Association OK!, receive A-ASSOCIATE-RSP")
            
            // Issue A-ASSOCIATE confirmation (accept) primitiveNext state is Sta6
            
            // if assoc rejected, return .Sta1

            // Return the new state
            return .Sta6
        }
    }
    
    
    func AE6(assoc: DicomAssociation) -> Transition {
        return {
            // Association ready for data transfer
            Logger.info("Association ready for data transfer")
                        
            // Return the new state
            return .Sta3
        }
    }
    
    
    
    
    
    func DT1(assoc: DicomAssociation) -> Transition {
        return {
            // P-DATA request primitive
            Logger.info("P-DATA request primitive")
                        
            // Return the new state
            return .Sta6
        }
    }
    
    
    
    
    func AA8(assoc: DicomAssociation) -> Transition {
        return {
            // Data Transfer started
            Logger.info("Data Transfer started")
            
            // Return the new state
            return .Sta13
        }
    }
}

