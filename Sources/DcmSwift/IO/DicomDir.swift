//
//  File.swift
//  
//
//  Created by Colombe on 29/06/2021.
//

import Foundation

/**
    Class representing a Dicom Directory and all associated methods.
    DICOMDIR stores the informatique about a DICOM files in a given file directoru (folder). Thus, DICOMDIR plays the role of
    a small DICOM database, or an index of DICOM files, placed in the root folder of the media (like a DVD).
 */
public class DicomDir:DicomFile {
    
    //MARK: Properties
    
    private var offset:Int = 0
    private var offsetFirst:Int = 0
    private var offsetLast:Int = 0
    
    public var index:[String] = []
    
    // PatientID:PatientName
    public var patients:[String:String] = [:]
    public var patientsKeys:[String] = []
    
    // StudyInstanceUID:[PatientID,StudyDate,StudyTime,AccessionNumber,StudyDescription]
    public var studies:[String:[String:Any]] = [:]
    public var studiesKeys:[String] = []
    
    // SeriesInstanceUID:[StudyInstanceUID,SeriesNumber]
    public var series:[String:[String:String]] = [:]
    public var seriesKeys:[String] = []
    
    // ReferencedSOPInstanceUIDInFile:[SeriesInstanceUID,filepath,DateImage,TimeImage]
    public var images:[String:[String:Any]] = [:]
    public var imagesKeys:[String] = []
    
    // MARK: Methods
    
    /**
        Load a DICOMDIR for a given path
     */
    public override init?(forPath filepath: String) {
        super.init(forPath: filepath)
    }
    
    /**
        Create a void DICOMDIR
     */
    public override init() {
        super.init()
    }
    
    /**
        Return a boolean that indicates if a file is a DICOMDIR. 
    */
    public static func isDicomDir(forPath filepath: String) -> Bool {
        let inputStream = DicomInputStream(filePath: filepath)
        
        do {
            if let dataset = try inputStream.readDataset() {
                
                if dataset.hasElement(forTagName:"DirectoryRecordSequence") {
                    return true
                } else {
                    return false
                }
            }
        } catch _ {
            return false
        }
        return false
    }
    
    /**
        Read a DicomDir surcharging the DicomFile read method
     */
    override func read() -> Bool {
        let rez = super.read()
        
        if rez == false {
            return false
        }
        
        load()
        
        return rez
    }
    
    /**
        Return an array of String wich represents all the DICOM files corresponding to a given patient
    */
    public func index(forPatientID givenID:String) -> [String] {
        var resultat : [String] = []
        
        for(patientsID,_) in patients {
            if(patientsID == givenID) {
                for studyUID in studiesKeys {
                    if let studyDictionary = studies[studyUID] {
                        let paID = studyDictionary["PatientID"] as? String
                        if(patientsID == paID) {
                            for seriesUID in seriesKeys {
                                if let seriesDictionary = series[seriesUID] {
                                    if(studyUID == seriesDictionary["StudyInstanceUID"]) {
                                        for imgSOPinstance in imagesKeys {
                                            if let imagesDictionary = images[imgSOPinstance] {
                                                if(seriesUID == imagesDictionary["SeriesInstanceUID"] as? String) {
                                                    let path = imagesDictionary["ReferencedFileID"] ?? ""
                                                    let pathString = "\(path)"
                                                    if(pathString != DicomDir.amputation(forPath: filepath)) {
                                                        resultat.append(pathString)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultat
    }
    
    /**
        Return an array of String wich represents all the DICOM files corresponding to a given study
     */
    public func index(forStudyInstanceUID givenStudyUID:String) -> [String] {
        var resultat : [String] = []
        
        for _ in patientsKeys {
            for studyUID in studiesKeys {
                if(studyUID == givenStudyUID) {
                    for(seriesUID, _) in series {
                        if let seriesDictionary = series[seriesUID] {
                            if(studyUID == seriesDictionary["StudyInstanceUID"]) {
                                for imgSOPinstance in imagesKeys {
                                    if let imagesDictionary = images[imgSOPinstance] {
                                        if(seriesUID == imagesDictionary["SeriesInstanceUID"] as? String) {
                                            let path = imagesDictionary["ReferencedFileID"] ?? ""
                                            let pathString = "\(path)"
                                            if(pathString != DicomDir.amputation(forPath: filepath)) {
                                                resultat.append(pathString)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultat
    }
    
    /**
        Return an array of String wich represents all the DICOM files corresponding to a given serie
     */
    public func index(forSeriesInstanceUID givenSeriesUID:String) -> [String] {
        var resultat : [String] = []
        
        for _ in patientsKeys {
            for _ in studiesKeys {
                for seriesUID in seriesKeys {
                    if(seriesUID == givenSeriesUID) {
                        for imgSOPinstance in imagesKeys {
                            if let imagesDictionary = images[imgSOPinstance] {
                                if(seriesUID == imagesDictionary["SeriesInstanceUID"] as? String) {
                                    let path = imagesDictionary["ReferencedFileID"] ?? ""
                                    let pathString = "\(path)"
                                    if(pathString != DicomDir.amputation(forPath: filepath)) {
                                        if !resultat.contains(pathString) {
                                            resultat.append(pathString)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultat
    }
    
    /**
        Return a String without the last part (after the last /)
     */
    public static func amputation(forPath filepath: String) -> String {
        var stringAmputee = ""
        let array = filepath.components(separatedBy: "/")
        let size = array.count
        for i in 0 ..< size-1 {
            if i == size-2 {
                stringAmputee += array[i]
            } else {
                stringAmputee += array[i] + "/"
            }
        }
        return stringAmputee
    }
    
    //MARK: Read a DicomDir
    
    /**
        Load all the properties of a DicomDir instance (patients, index etc)
     */
    private func load() {
        if let dataset = self.dataset {
            if let directoryRecordSequence = dataset.element(forTagName: "DirectoryRecordSequence") as? DataSequence {
                
                var patientName     = ""
                var patientID       = ""
                
                var studyUID        = ""
                var studyDate       = ""
                var studyTime       = ""
                var accessionNb     = ""
                var studyDescri     = ""
                var studyID         = ""
                
                var modality        = ""
                var serieUID        = ""
                var seriesNb        = ""
                
                var path            = ""
                var SOPClassUID     = ""
                var SOPUID          = ""
                var transferSyntax  = ""
                var instanceNb      = ""
                
                for item in directoryRecordSequence.items {
                    
                    for element in item.elements {
                    // Load the index property
                        if(element.name == "ReferencedFileID") {
                            path = DicomDir.amputation(forPath: filepath)
                            
                            for dataValue in element.values {
                                path += "/" + dataValue.value
                            }
                            if(path != DicomDir.amputation(forPath: filepath)) {
                                index.append(path)
                            }
                        } 
                         
                    // Load the patients property
                        if element.name == "PatientName" {
                            patientName = "\(element.value)"
                        }
                            
                        if element.name == "PatientID" {
                            patientID = "\(element.value)"
                        }
                        
                    // Load the studies property
                        if element.name == "StudyInstanceUID" {
                            studyUID = "\(element.value)"
                        }
                    
                        if var studyDictionary:[String:Any] = studies[studyUID] {
                            studyDictionary["PatientID"] = patientID
                            
                            if element.name == "StudyDate" {
                                studyDate = "\(element.value)"
                                studyDictionary["StudyDate"] = studyDate
                            }
                            
                            if element.name == "StudyTime" {
                                studyTime = "\(element.value)"
                                studyDictionary["StudyTime"] = studyTime
                            }
                            
                            if element.name == "AccessionNumber" {
                                accessionNb = "\(element.value)"
                                studyDictionary["AccessionNumber"] = accessionNb
                            }
                            
                            if element.name == "StudyDescription" {
                                studyDescri = "\(element.value)"
                                studyDictionary["StudyDescription"] = studyDescri
                            }
                            
                            if element.name == "StudyID" {
                                studyID = "\(element.value)"
                                studyDictionary["StudyID"] = studyID
                            }
                        }
                        
                    // Load the series property
                        if element.name == "SeriesInstanceUID" {
                            serieUID = "\(element.value)"
                        }
                        
                        if var serieDictionary:[String:String] = series[serieUID] {
                            
                            if element.name == "Modality" {
                                modality = "\(element.value)"
                                serieDictionary["Modality"] = modality
                            }
                
                            if element.name == "SeriesNumber" {
                                seriesNb = "\(element.value)"
                                serieDictionary["SeriesNumber"] = seriesNb
                            }
                        }
                    
                    // Load the images property
                        if element.name == "ReferencedSOPInstanceUIDInFile" {
                            SOPUID = "\(element.value)"
                        }
                        
                        if var imageDictionary:[String:Any] = images[SOPUID] {
                            
                            if element.name == "ReferencedFileID" {
                                path = "\(element.value)"
                                if SOPUID.count > 0 && serieUID.count > 0 {
                                    if(path != DicomDir.amputation(forPath: filepath)) {
                                        imageDictionary["ReferencedFileID"] = path
                                    }
                                }
                            }
                            
                            imageDictionary["SeriesInstanceUID"] = serieUID
                            
                            if element.name == "InstanceNumber" {
                                instanceNb = "\(element.value)"
                                if SOPUID.count > 0 && serieUID.count > 0 {
                                    if(path != DicomDir.amputation(forPath: filepath)) {
                                        imageDictionary["InstanceNumber"] = instanceNb
                                    }
                                }
                            }
                            
                            if element.name == "ReferencedSOPClassUIDInFile" {
                                SOPClassUID = "\(element.value)"
                                imageDictionary["ReferencedSOPClassUIDInFile"] = SOPClassUID
                            }
                            
                            if element.name == "ReferencedTransferSyntaxUIDInFile" {
                                transferSyntax = "\(element.value)"
                                imageDictionary["ReferencedTransferSyntaxUIDInFile"] = transferSyntax
                            }
                        }
                    }
                    
                    if patientName.count > 0 && patientID.count > 0 {
                        patients[patientID] = patientName
                        patientsKeys.append(patientID)
                    }
                }
            }
        }
    }
    
    /**
        Recursive method to browse a directory, return a string array containing all the filepaths
     */
    private static func browse(atPath folderPath:String) -> [String] {
        var paths:[String] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folderPath)
            
            for file in files {
                var pathFolder = folderPath
                
                if(pathFolder.last != "/") {
                    pathFolder += "/"
                }
                
                let filepath = pathFolder + file
                
                // ignore invisible system files
                if file.first == "." {
                    continue
                }
                
                // switch between folder/file
                var isDir:ObjCBool = false
                                
                if FileManager.default.fileExists(atPath: filepath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // if dir
                        let files = browse(atPath: filepath)
                        
                        paths.append(contentsOf: files)
                    }
                    else {
                        // if file
                        paths.append(filepath)
                    }
                }
            }
        } catch {
            
        }
        
        return paths
    }
    
    /**
        Create a DicomDir instance wich contains the interesting data of the given folder
     */
    public static func parse(atPath folderPath:String) -> DicomDir? {
        
        let dcmDir = DicomDir.init()
        dcmDir.filepath = amputation(forPath:folderPath)
        
        var pathFolder = folderPath
        if(pathFolder.last != "/") {
            pathFolder += "/"
        }
            
        let files = DicomDir.browse(atPath: folderPath)
        
        for absolutePath in files {
            // add to DicomDir.index the file path
            dcmDir.index.append(absolutePath)
            
            guard let dcmFile = DicomFile(forPath: absolutePath) else {
                return nil
            }
        
            // fill patient property
            let patientKey = dcmFile.dataset.string(forTag: "PatientID")
            let patientVal = dcmFile.dataset.string(forTag: "PatientName")
            if let key = patientKey {
                dcmDir.patients[key] = patientVal
                if(!dcmDir.patientsKeys.contains(key)) {
                    dcmDir.patientsKeys.append(key)
                }
            }
            
            // fill study property
            let studyKey = dcmFile.dataset.string(forTag: "StudyInstanceUID")
            let date = dcmFile.dataset.string(forTag: "StudyDate")
            let time = dcmFile.dataset.string(forTag: "StudyTime")
            let accession = dcmFile.dataset.string(forTag: "AccessionNumber")
            let description = dcmFile.dataset.string(forTag: "StudyDescription")
            let studyID = dcmFile.dataset.string(forTag: "StudyID")
            let studyVal = patientKey
            
            if let key = studyKey {
                if dcmDir.studies[key] == nil {
                    
                    var studyDictionary:[String:Any] = [:]
                        
                    studyDictionary["PatientID"] = studyVal as Any
                        
                    if(!dcmDir.studiesKeys.contains(key)) {
                        dcmDir.studiesKeys.append(key)
                    }
                        
                    if let d = date {
                        studyDictionary["StudyDate"] = d as Any
                    }
                    if let t = time {
                        studyDictionary["StudyTime"] = t as Any
                    }
                    if let a = accession {
                        studyDictionary["AccessionNumber"] = a as Any
                    }
                    if let descri = description {
                            studyDictionary["StudyDescription"] = descri as Any
                    }
                    if let stID = studyID {
                        studyDictionary["StudyID"] = stID as Any
                    }
                    dcmDir.studies[key] = studyDictionary
                }
            }
            
            // fill serie property
            let serieUID = dcmFile.dataset.string(forTag: "SeriesInstanceUID")
            let seriesNumber = dcmFile.dataset.string(forTag: "SeriesNumber")
            let modality = dcmFile.dataset.string(forTag: "Modality")
            if let key = serieUID {
                if dcmDir.series[key] == nil {
                    
                    var serieDictionary:[String:String] = [:]
                    
                    if let seNb = seriesNumber {
                        serieDictionary["SeriesNumber"] = seNb as String
                    }
                    
                    if let seVal = studyKey {
                        serieDictionary["StudyInstanceUID"] = seVal as String
                    }
                    
                    if let m = modality {
                        serieDictionary["Modality"] = m as String
                    }
                    
                    if(!dcmDir.seriesKeys.contains(key)) {
                        dcmDir.seriesKeys.append(key)
                    }
                    dcmDir.series[key] = serieDictionary
                }
            }
            
            // fill images property
            let imageSOPinstance = dcmFile.dataset.string(forTag: "SOPInstanceUID")
            let syntax = dcmFile.dataset.string(forTag: "TransferSyntaxUID")
            let instanceNumber = dcmFile.dataset.string(forTag: "InstanceNumber")
            let SOPClassUID = dcmFile.dataset.string(forTag: "SOPClassUID")
            
            let index = pathFolder.lastIndex(of: "/")
            let imgPath = absolutePath[index!...]
            let pathFormatted = String(formatPath(forPath: String(imgPath)))
            
            if let key = imageSOPinstance {
                if dcmDir.images[key] == nil {
                    
                    if(!dcmDir.imagesKeys.contains(key)) {
                        dcmDir.imagesKeys.append(key)
                    }
                    
                    var imageDictionary:[String:Any] = [:]
                    
                    imageDictionary["ReferencedFileID"] = pathFormatted as Any
                    
                    if let insNb = instanceNumber {
                        imageDictionary["InstanceNumber"] = insNb as Any
                    }
                    
                    if let seUID = serieUID {
                        imageDictionary["SeriesInstanceUID"] = seUID as Any
                    }
                    
                    if let syn = syntax {
                        imageDictionary["ReferencedTransferSyntaxUIDInFile"] = syn as Any
                    }
                    
                    if let sopclass = SOPClassUID {
                        imageDictionary["ReferencedSOPClassUIDInFile"] = sopclass as Any
                    }
                    
                    dcmDir.images[key] = imageDictionary
                }
            }
        }

        return dcmDir
    }
    
    /**
        Input : a path delimited by "/". Output : a path delimited by "\".
     */
    public static func formatPath(forPath path:String) -> String {
        let components = path.components(separatedBy: "/")
        var result:String = ""
        for substring in components {
            result += substring
            result += "\\"
        }
        result.remove(at: result.index(before: result.endIndex))
        result.removeFirst()
        return result
    }
    
//    private func truncate(forPath filepath: String) -> String  {
//        return NSString(string: filepath).deletingLastPathComponent
//    }
    /*
    //MARK: Write a DicomDir
    
    /**
        Create the DirectoryRecordSequence using the given properties : patients, studies, series, images.
     */
    public func createDirectoryRecordSequence() -> DataSequence? {
        // All the useful tags
        let dataTag = DataTag.init(withGroup: "0004", element: "1220", byteOrder: .LittleEndian)
        let tagItem = DataTag.init(withGroup: "fffe", element: "e000", byteOrder: .LittleEndian)
        
        let tagNextRecord = DataTag.init(withGroup: "0004", element: "1400", byteOrder: .LittleEndian)
        let tagRecordInUseFlag = DataTag.init(withGroup: "0004", element: "1410", byteOrder: .LittleEndian)
        let tagLowerRecord = DataTag.init(withGroup: "0004", element: "1420", byteOrder: .LittleEndian)
        let tagType = DataTag.init(withGroup: "0004", element: "1430", byteOrder: .LittleEndian)
        let tagCharacterSet = DataTag.init(withGroup: "0008", element: "0005", byteOrder: .LittleEndian)
        let tagID = DataTag.init(withGroup: "0010", element: "0020", byteOrder: .LittleEndian)
        let tagName = DataTag.init(withGroup: "0010", element: "0010", byteOrder: .LittleEndian)
        
        let tagstID = DataTag.init(withGroup: "0020", element: "000d", byteOrder: .LittleEndian)
        let tagstDate = DataTag.init(withGroup: "0008", element: "0020", byteOrder: .LittleEndian)
        let tagstTime = DataTag.init(withGroup: "0008", element: "0030", byteOrder: .LittleEndian)
        let tagAccession = DataTag.init(withGroup: "0008", element: "0050", byteOrder: .LittleEndian)
        let tagstDescription = DataTag.init(withGroup: "0008", element: "1030", byteOrder: .LittleEndian)
        
        let tagseID = DataTag.init(withGroup: "0020", element: "000e", byteOrder: .LittleEndian)
        let tagseNb = DataTag.init(withGroup: "0020", element: "0011", byteOrder: .LittleEndian)
        
        let tagSOP = DataTag.init(withGroup: "0004", element: "1511", byteOrder: .LittleEndian)
        let tagPath = DataTag.init(withGroup: "0004", element: "1500", byteOrder: .LittleEndian)
        let tagSOPClass = DataTag.init(withGroup: "0004", element: "1510", byteOrder: .LittleEndian)
        let tagInstanceNumber = DataTag.init(withGroup: "0020", element: "0013", byteOrder: .LittleEndian)
        
        // Creation of the sequence
        let sequence:DataSequence = DataSequence(withTag: dataTag, parent: nil)
        var cpt = 1
        offset += sequence.toData().count
        
        for patientID in patientsKeys {
            
            let item = DataItem(withTag: tagItem, parent: sequence)
            if(cpt == 1) {
                offsetFirst = offset
                offsetLast = 0
            } else if(cpt == patients.count) {
                offsetLast = offset
            }
            
            offset += item.toData().count
            
            sequence.items.append(item)
            
            let paOffsetNext = addValue(addInteger: 4820, forTag: tagNextRecord, withParent: item)
            item.elements.append(paOffsetNext)
            
            let recordInUseFlag = addValue(addInteger: 0, forTag: tagRecordInUseFlag, withParent: item)
            item.elements.append(recordInUseFlag)
            
            let paOffsetLower = addValue(addInteger: 486, forTag: tagLowerRecord, withParent: item)
            item.elements.append(paOffsetLower)
            
            let paType = addValue(addString: "PATIENT", forTag: tagType, withParent: item)
            item.elements.append(paType)
            
            let characterSet = addValue(addString: "ISO_IR 100", forTag: tagCharacterSet, withParent: item)
            item.elements.append(characterSet)
            
            if let p = patients[patientID] {
                let paName = addValue(addString: p, forTag: tagName, withParent: item)
                item.elements.append(paName)
            }
            
            let paID = addValue(addString: patientID, forTag: tagID, withParent: item)
            item.elements.append(paID)
            
            for studyID in studiesKeys {
                if let studyArray = studies[studyID] {
                
                    if(patientID == (studyArray[0]) as? String) {
                        
                        let item = DataItem(withTag: tagItem, parent: sequence)
                        sequence.items.append(item)
                        
                        let studyOffsetNext = addValue(addInteger: 0, forTag: tagNextRecord, withParent: item)
                        item.elements.append(studyOffsetNext)
                        
                        item.elements.append(recordInUseFlag)
                        offset += recordInUseFlag.toData().count
                        
                        let studyOffsetLower = addValue(addInteger: 704, forTag: tagLowerRecord, withParent: item)
                        item.elements.append(studyOffsetLower)
                        
                        let studyType = addValue(addString: "STUDY", forTag: tagType, withParent: item)
                        item.elements.append(studyType)
                        
                        item.elements.append(characterSet)
                        
                        let dateString = String(describing: studyArray[1])
                        var stDate = ""
                        
                        if let index = dateString.firstIndex(of: " ") {
                            let dCut = dateString[..<index]
                            stDate = dCut.replacingOccurrences(of: "-", with: "")
                        }
                        
                        let studyDate = addValue(addString: stDate, forTag: tagstDate, withParent: item)
                        item.elements.append(studyDate)
                        
                        let timeString = String(describing: studyArray[2])
                        let components:[String] = timeString.components(separatedBy: " ")
                        let compo:[String] = components[1].components(separatedBy: ":")
                        let stTime = compo[0] + compo[1] + compo[2]
                        
                        let studyTime = addValue(addString: stTime, forTag: tagstTime, withParent: item)
                        item.elements.append(studyTime)
                        
                        let accessionNumber = addValue(addString: "\(studyArray[3])", forTag: tagAccession, withParent: item)
                        item.elements.append(accessionNumber)
                        
                        let studyDescri = addValue(addString: "\(studyArray[3])", forTag: tagstDescription, withParent: item)
                        item.elements.append(studyDescri)
                        
                        let studyInstanceUID = addValue(addString: studyID, forTag: tagstID, withParent: item)
                        item.elements.append(studyInstanceUID)
                        
                        //TODO: add studyID
                        
                        for serieID in seriesKeys {
                            
                            if let arraySerie = series[serieID] {
                                
                                if(studyID == arraySerie[0]) {
                                    
                                    let serieNumber:String = arraySerie[1]
                                    let item = DataItem(withTag: tagItem, parent: sequence)
                                    sequence.items.append(item)
                                    
                                    let serieOffsetNext = addValue(addInteger: 0, forTag: tagNextRecord, withParent: item)
                                    item.elements.append(serieOffsetNext)
                                    
                                    item.elements.append(recordInUseFlag)
                                    offset += recordInUseFlag.toData().count
                                    
                                    let serieOffsetLower = addValue(addInteger: 846, forTag: tagLowerRecord, withParent: item)
                                    item.elements.append(serieOffsetLower)
                                    
                                    let serieType = addValue(addString: "SERIES", forTag: tagType, withParent: item)
                                    item.elements.append(serieType)
                                    
                                    //TODO: add modality
                                    
                                    let serieInstanceUID = addValue(addString: serieID, forTag: tagseID, withParent: item)
                                    item.elements.append(serieInstanceUID)
                                    
                                    let serieNum = addValue(addString: serieNumber, forTag: tagseNb, withParent: item)
                                    item.elements.append(serieNum)
                                    
                                    for sop in imagesKeys {
                                        
                                        if let array = images[sop] {
                                        
                                            if("\(array[0])" == serieID) {
                                                let pathImage = "\(array[1])"
                                                let item = DataItem(withTag: tagItem, parent: sequence)
                                                sequence.items.append(item)
                                                
                                                let imageOffsetNext = addValue(addInteger: 1466, forTag: tagNextRecord, withParent: item)
                                                item.elements.append(imageOffsetNext)
                                                
                                                item.elements.append(recordInUseFlag)
                                                
                                                let imageOffsetLower = addValue(addInteger: 0, forTag: tagLowerRecord, withParent: item)
                                                item.elements.append(imageOffsetLower)
                                                
                                                let imageType = addValue(addString: "IMAGE", forTag: tagType, withParent: item)
                                                item.elements.append(imageType)
                                                
                                                let imagePath = addValue(addString: pathImage, forTag: tagPath, withParent: item)
                                                item.elements.append(imagePath)
                                                
                                                //TODO : ci dessous
                                                let imageSOPClass = addValue(addString: "TO DO", forTag: tagSOPClass, withParent: item)
                                                item.elements.append(imageSOPClass)
                                                
                                                let imageSOP = addValue(addString: sop, forTag: tagSOP, withParent: item)
                                                item.elements.append(imageSOP)
                                                
                                                //TODO: add referenced transfer syntax
                                                
                                                let instanceNumber = addValue(addInteger: 0, forTag: tagInstanceNumber, withParent: item) //TODO
                                                item.elements.append(instanceNumber)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            cpt += 1
        }
        print("offsetFirst \(offsetFirst)")
        print("offsetLast \(offsetLast)")
        
        return sequence
    }

    /**
        Add a String value to the Directory Record Sequence
     */
    private func addValue(addString value:String, forTag tag:DataTag, withParent parent:DataElement?) -> DataElement {
        let element = DataElement(withTag: tag, parent: parent)
        _ = element.setValue(value)
        offset += element.toData().count
        return element
    }
    
    /**
        Add an integer value  to the Directory Record Sequence
     */
    private func addValue(addInteger value:Int, forTag tag:DataTag, withParent parent:DataElement?) -> DataElement {
        let element = DataElement(withTag: tag, parent: parent)
        _ = element.setValue(value)
        offset += element.toData().count
        return element
    }
    
    /**
        Write a new DICOMDIR using a folder
     */
    public func writeDicomDir(atPath folderPath:String) -> Bool {
        hasPreamble = true
        dataset = DataSet()
        
        // Write the Prefix Header
        _ = dataset.set(value: UInt32(0).bigEndian, forTagName: "FileMetaInformationGroupLength")
        _ = dataset.set(value: Data(repeating: 0x00, count: 2), forTagName: "FileMetaInformationVersion") // WRONG DATA
        _ = dataset.set(value: "1.2.840.10008.1.3.10", forTagName: "MediaStorageSOPClassUID")
        _ = dataset.set(value: "2.25.263396925751148424850033748771929175867", forTagName: "MediaStorageSOPInstanceUID")
        _ = dataset.set(value: "1.2.840.10008.1.2.1", forTagName: "TransferSyntaxUID")
        _ = dataset.set(value: "1.2.40.0.13.1.3", forTagName: "ImplementationClassUID")
        _ = dataset.set(value: "dcm4che-5.23.3", forTagName: "ImplementationVersionName")
        
        let headerCount = dataset.toData().count
        _ = dataset.set(value: UInt32(headerCount-12).bigEndian, forTagName: "FileMetaInformationGroupLength") // headerCount - 12 car on ne compte pas les bytes de FileMetaInformationGroupLength

        offset += 132 // 128 bytes preamble + 4 bytes
        offset += headerCount
        
        // Write the DataSet
        _ = dataset.set(value: "", forTagName: "FileSetID")
        let sizeFileSetID = dataset.toData().count - headerCount
        offset += sizeFileSetID
        
        _ = dataset.set(value: UInt32(000).bigEndian, forTagName:  "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity") // offsetFirst
        _ = dataset.set(value: UInt32(0000).bigEndian, forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity") // offsetLast
        _ = dataset.set(value: UInt16(0).bigEndian, forTagName: "FileSetConsistencyFlag")
        
        let sizeAfterOffset = dataset.toData().count - headerCount - sizeFileSetID
        offset += sizeAfterOffset
                
        // Write the DirectoryRecordSequence
        if let c:DataSequence = createDirectoryRecordSequence() {
            c.length = -1
            for item in c.items {
                item.length = -1
            }
            dataset.add(element: c as DataElement)
        }
        
        _ = dataset.set(value: UInt32(offsetFirst).bigEndian, forTagName:  "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity") // offsetFirst
        _ = dataset.set(value: UInt32(offsetLast).bigEndian, forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity") // offsetLast
        
        dataset.hasPreamble = hasPreamble
        
        let dicomDirPAth = folderPath.last == "/" ? folderPath + "DICOMDIR" : folderPath + "/DICOMDIR"
        
        return self.write(atPath: dicomDirPAth)
    }*/
}
