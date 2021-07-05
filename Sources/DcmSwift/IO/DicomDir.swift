//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 29/06/2021.
//

import Foundation


public class DicomDir : DicomFile {
    /**
     List all files path at IMAGE level found in the DICOMDIR
     
     File path is determined by ReferencedFileID and is returned in its absolute form,
     relative to the file path of the DICOMDIR given at init()
     */
    public var filePaths:[String]           = []
    /**
     List of all patients (PatientID:PatientName)
     */
    public var patients:[String:String]     = [:]
    /**
     List of all studies (StudyUID:PatientID)
     */
    public var studies:[String:String]      = [:]
    /**
     List of all series (SeriesUID:StudyUID)
     */
    public var series:[String:String]       = [:]
    /**
     List of all images (SopUID:[SeriesUID, FilePath])
     */
    public var images:[String:[String]]     = [:]
    
    
    
    // MARK: -
    override func read() -> Bool {
        let rez = super.read()
        
        if rez == false {
            return rez
        }
        
        // supplement with readDicomDirDataset
        readDicomDirDataset()
        
        return rez
    }
    
    
    public func imagePaths(forPatientID patientID:String) -> [String] {
        var paths:[String] = []
        
        for (suid, pid) in studies {
            if pid == patientID {
                for (seuid, stuid) in series {
                    if stuid == suid {
                        for (_, array) in images {
                            print("array.first \(array.first!)")
                            print("seuid       \(seuid)")
                            if let path = array.last, array.first == seuid {
                                paths.append(path)
                            }
                        }
                    }
                }
            }
        }
        
        return paths
    }

    
    // MARK: -
    private func readDicomDirDataset() {
        if let dataset = self.dataset {
            if let directoryRecordSequence = dataset.element(forTagName: "DirectoryRecordSequence") as? DataSequence {
                // temporary items for patient, study, series, etc.
                var patientItem:DataItem?   = nil
                var studyItem:DataItem?     = nil
                var seriesItem:DataItem?    = nil
                var imageItem:DataItem?     = nil
                
                for item in directoryRecordSequence.items {
                    var directoryRecordType:String?
                    var referencedFileID:String = ""
                    
                    // gather informations from elements
                    for el in item.elements {
                        if el.name == "DirectoryRecordType" {
                            // first we get the type
                            if let drt = el.value as? String {
                                directoryRecordType = drt.trimmingCharacters(in: CharacterSet.whitespaces)
                            }
                            
                            // we keep a temp ref of item by type
                            if directoryRecordType == "PATIENT" {
                                patientItem = item
                            }
                            else if directoryRecordType == "STUDY" {
                                studyItem = item
                            }
                            else if directoryRecordType == "SERIES" {
                                seriesItem = item
                            }
                            else if directoryRecordType == "IMAGE" {
                                imageItem = item
                            }
                        }
                        else if el.name == "ReferencedFileID" {
                            if directoryRecordType == "IMAGE" {
                                for v in el.values {
                                    referencedFileID += "\(absoluteDicomDirRoot)/\(v.value)"
                                }
                            }
                        }
                        
                    }
                    
                    // for each element type
                    if directoryRecordType == "IMAGE" {
                        if referencedFileID.count > 0 {
                            if let s = seriesItem, let i = imageItem {
                                if let seuid    = s.element(withName: "SeriesInstanceUID")?.value as? String,
                                   let sopuid   = i.element(withName: "ReferencedSOPInstanceUIDInFile")?.value as? String {
                                    images[seuid] = [sopuid, referencedFileID]
                                }
                            }
                        
                            if !filePaths.contains(referencedFileID) {
                                filePaths.append(referencedFileID)
                            }
                        }
                    } else if directoryRecordType == "PATIENT" {
                        if let i = patientItem {
                            if let pid      = i.element(withName: "PatientID")?.value as? String,
                               let pname    = i.element(withName: "PatientName")?.value as? String {
                                patients[pid] = pname.trimmingCharacters(in: CharacterSet.whitespaces)
                            }
                        }
                    } else if directoryRecordType == "STUDY" {
                        if let p = patientItem, let i = studyItem {
                            if let pid      = p.element(withName: "PatientID")?.value as? String,
                               let stuid    = i.element(withName: "StudyInstanceUID")?.value as? String {
                                studies[stuid] = pid.trimmingCharacters(in: CharacterSet.whitespaces)
                            }
                        }
                    } else if directoryRecordType == "SERIES" {
                        if let s = studyItem, let ss = seriesItem {
                            if let stuid    = s.element(withName: "StudyInstanceUID")?.value as? String,
                               let seuid    = ss.element(withName: "SeriesInstanceUID")?.value as? String {
                                series[seuid] = stuid.trimmingCharacters(in: CharacterSet.whitespaces)
                            }
                        }
                    }
                }
            }
        }
    }

    
    private var absoluteDicomDirRoot:String {
        NSString(string: self.filepath).deletingLastPathComponent
    }
}
