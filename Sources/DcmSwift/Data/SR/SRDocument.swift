//
//  SRDocument.swift
//  
//
//  Created by Rafael Warnault, OPALE on 05/07/2021.
//

import Foundation

/**
 SR document types (DICOM IOD)
 
 Pasted from DCMTK for reference:
 
 https://support.dcmtk.org/docs/classDSRTypes.html#a6545d88cf751a0b97c56c509dc644b85
 */
public enum DocumentType {
    case BasicTextSR                                // DICOM IOD: Basic Text SR.
    case EnhancedSR                                 // DICOM IOD: Enhanced SR.
    case ComprehensiveSR                            // DICOM IOD: Comprehensive SR.
    case KeyObjectSelectionDocument                 // DICOM IOD: Key Object Selection Document.
    case MammographyCadSR                           // DICOM IOD: Mammography CAD SR.
    case ChestCadSR                                 // DICOM IOD: Chest CAD SR.
    case ColonCadSR                                 // DICOM IOD: Colon CAD SR.
    case ProcedureLog                               // DICOM IOD: Procedure Log.
    case XRayRadiationDoseSR                        // DICOM IOD: X-Ray Radiation Dose SR.
    case SpectaclePrescriptionReport                // DICOM IOD: Spectacle Prescription Report.
    case MacularGridThicknessAndVolumeReport        // DICOM IOD: Macular Grid Thickness and Volume Report.
    case ImplantationPlanSRDocument                 // DICOM IOD: Implantation Plan SR Document.
    case Comprehensive3DSR                          // DICOM IOD: Comprehensive 3D SR.
    case RadiopharmaceuticalRadiationDoseSR         // DICOM IOD: Radiopharmaceutical Radiation Dose SR.
    case ExtensibleSR                               // DICOM IOD: Extensible SR (not yet implemented)
    case AcquisitionContextSR                       // DICOM IOD: Acquisition Context SR.
    case SimplifiedAdultEchoSR                      // DICOM IOD: Simplified Adult Echo SR.
    case PatientRadiationDoseSR                     // DICOM IOD: Patient Radiation Dose SR.
    case PerformedImagingAgentAdministrationSR      // DICOM IOD: Performed Imaging Agent Administration SR.
    case PlannedImagingAgentAdministrationSR        // DICOM IOD: Planned Imaging Agent Administration SR.
    case RenditionSelectionDocument                 // DICOM IOD: Rendition Selection Document.
}


public enum PreliminaryFlag {
    case PRELIMINARY
    case FINAL
}

public enum VerificationFlag {
    case UNVERIFIED
    case VERIFIED
}

public enum CompletionFlag {
    case PARTIAL
    case COMPLETE
}

/**
 Class representing a DICOM Structured Report file
 This class provides specific tools and implementation to deals with DICOM SR document.
 */
public class SRDocument {
    private var dataset:DataSet
    private var root:SRNode
    
    public var preliminaryFlag:PreliminaryFlag      = .PRELIMINARY
    public var verificationFlag:VerificationFlag    = .UNVERIFIED
    public var completionFlag:CompletionFlag        = .PARTIAL
    
    public var contentDate:Date? {
        get {
            dataset.date(forTag: "ContentDate")
        }
    }
    
    public var contentTime:Date? {
        get {
            dataset.date(forTag: "ContentTime")
        }
    }
    
    /**
        Init a DICOM SR document with a given dataset
     */
    public init?(withDataset dataset:DataSet) {
        self.dataset = dataset
    
        self.root = SRNode(parent: nil, relationshipType: .root)
        
        if !load() {
            return nil
        }
    }
    
    
    private func load(force:Bool = false) -> Bool {
        // perform some sanity checks
        guard let modality = dataset.string(forTag: "Modality") else {
            Logger.error("Cannot load SR document, Modality tag not found")
            return false
        }
        
        if !force && modality != "SR" {
            Logger.error("Cannot load SR document, wrong modality given \(modality)")
            return false
        }
        
        // Load SR characteristics:
        /// * doc type (via IOD and SOP classes)
        /// * flags (in the file dataset)
        /// * etc.
        
        // load nodes
        guard let sequence = dataset.element(forTagName: "ContentSequence") as? DataSequence else {
            Logger.error("Cannot load SR document, no ContentSequence found")
            return false
        }
        
        return load(sequence: sequence, node: root)
    }
    
    
    private func load(sequence:DataSequence, node:SRNode) -> Bool {
        // loop items
        for item in sequence.items {
            if let irt = item.element
            
            let node = SRNode(parent: node, relationshipType: <#T##RelationshipType#>)
        }
        
        return false
    }
}
