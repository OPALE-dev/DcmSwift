//
//  FileViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class FileViewController: NSViewController {
    public var dicomFile:DicomFile!
    
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var sizeTextField: NSTextField!
    @IBOutlet weak var pathTextField: NSTextField!
    @IBOutlet weak var createdAtTextField: NSTextField!
    @IBOutlet weak var updatedAtTextField: NSTextField!
    
    @IBOutlet weak var sopTextField: NSTextField!
    @IBOutlet weak var tsTextField: NSTextField!
    @IBOutlet weak var byteOrderTextField: NSTextField!
    @IBOutlet weak var representationTextField: NSTextField!
    
    @IBOutlet weak var patientNameTextField: NSTextField!
    @IBOutlet weak var patientIDTextField: NSTextField!
    @IBOutlet weak var patientSexTextField: NSTextField!
    @IBOutlet weak var patientAgeTextField: NSTextField!
    
    @IBOutlet weak var modalityTextField: NSTextField!
    @IBOutlet weak var studyDescriptionTextField: NSTextField!
    @IBOutlet weak var studyDateTextField: NSTextField!
    @IBOutlet weak var studyTimeTextField: NSTextField!
    @IBOutlet weak var studyIDTextField: NSTextField!
    @IBOutlet weak var studyUIDTextField: NSTextField!
    
    @IBOutlet weak var seriesDescriptionTextField: NSTextField!
    @IBOutlet weak var seriesDateTextField: NSTextField!
    @IBOutlet weak var seriesTimeTextField: NSTextField!
    @IBOutlet weak var seriesUIDTextField: NSTextField!

    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let document:DicomDocument = representedObject as? DicomDocument {
                if document.dicomFile != nil {
                    self.dicomFile = document.dicomFile
                    self.updateUI()
                }
            }
        }
    }
    
    
    
    
    @IBAction func reveal(_ sender: Any) {
        NSWorkspace.shared.selectFile(self.dicomFile.filepath, inFileViewerRootedAtPath: "")
    }
    
    
    
    private func updateUI() {
        let df = DateFormatter()
        df.dateFormat = "YYY/MM/dd HH:mm:ss"
        
        self.nameTextField.stringValue              = (self.dicomFile.filepath as NSString).lastPathComponent
        self.pathTextField.stringValue              = self.dicomFile.filepath
        self.sizeTextField.stringValue              = self.dicomFile.fileSizeWithUnit()
        self.createdAtTextField.stringValue         = df.string(from: self.creationDate(forPath: self.dicomFile.filepath))
        self.updatedAtTextField.stringValue         = df.string(from: self.updateDate(forPath: self.dicomFile.filepath))
        
        if let mediaStorageSOPClassUID = self.dicomFile.dataset.string(forTag: "MediaStorageSOPClassUID") {
            self.sopTextField.stringValue           = DicomSpec.shared.nameForUID(withUID:mediaStorageSOPClassUID)
        }
        
        if let transferSyntaxUID = self.dicomFile.dataset.string(forTag: "TransferSyntaxUID") {
            self.tsTextField.stringValue            = DicomSpec.shared.nameForUID(withUID:transferSyntaxUID)
        }
        
        self.byteOrderTextField.stringValue         = "\(self.dicomFile.dataset.byteOrder)"
        self.representationTextField.stringValue    = "\(self.dicomFile.dataset.vrMethod)"
        
        self.patientNameTextField.stringValue       = self.dicomFile.dataset.string(forTag: "PatientName") ?? ""
        self.patientIDTextField.stringValue         = self.dicomFile.dataset.string(forTag: "PatientID") ?? ""
        self.patientSexTextField.stringValue        = self.dicomFile.dataset.string(forTag: "PatientSex") ?? ""
        self.patientAgeTextField.stringValue        = self.dicomFile.dataset.string(forTag: "PatientAge") ?? ""
        
        self.modalityTextField.stringValue          = self.dicomFile.dataset.string(forTag: "Modality") ?? ""
        self.studyDescriptionTextField.stringValue  = self.dicomFile.dataset.string(forTag: "StudyDescription") ?? ""
        self.studyDateTextField.stringValue         = self.dicomFile.dataset.string(forTag: "StudyDate") ?? ""
        self.studyTimeTextField.stringValue         = self.dicomFile.dataset.string(forTag: "StudyTime") ?? ""
        self.studyIDTextField.stringValue           = self.dicomFile.dataset.string(forTag: "StudyID") ?? ""
        self.studyUIDTextField.stringValue          = self.dicomFile.dataset.string(forTag: "StudyInstanceUID") ?? ""
        
        self.seriesDescriptionTextField.stringValue  = self.dicomFile.dataset.string(forTag: "SeriesDescription") ?? ""
        self.seriesDateTextField.stringValue         = self.dicomFile.dataset.string(forTag: "SeriesDate") ?? ""
        self.seriesTimeTextField.stringValue         = self.dicomFile.dataset.string(forTag: "SeriesTime") ?? ""
        self.seriesUIDTextField.stringValue          = self.dicomFile.dataset.string(forTag: "SeriesInstanceUID") ?? ""
    }
    
    
    
    private func creationDate(forPath:String) -> Date {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: forPath)
            return attr[FileAttributeKey.creationDate] as! Date
        } catch {
            print("Error: \(error)")
            return Date()
        }
    }
    
    
    private func updateDate(forPath:String) -> Date {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: forPath)
            return attr[FileAttributeKey.modificationDate] as! Date
        } catch {
            print("Error: \(error)")
            return Date()
        }
    }
    
    
    private func fileSize(forPath:String) -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: forPath)
            return attr[FileAttributeKey.size] as! UInt64
        } catch {
            print("Error: \(error)")
            return 0
        }
    }
}
