//
//  RemoteQueryViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 07/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let queryDidChange = Notification.Name(rawValue: "queryDidChange")
}


class RemoteQueryViewController: NSViewController {
    @IBOutlet weak var searchTextField: NSSearchField!
    @IBOutlet weak var searchPopUpButton: NSPopUpButton!
    
    @IBOutlet weak var timeAllDate:     NSButton!
    @IBOutlet weak var timeTodayAM:     NSButton!
    @IBOutlet weak var timeTodayPM:     NSButton!
    @IBOutlet weak var timeToday:       NSButton!
    @IBOutlet weak var timeYesterday:   NSButton!
    @IBOutlet weak var timeLast2Days:   NSButton!
    @IBOutlet weak var timeLast7Days:   NSButton!
    @IBOutlet weak var timeLastMonth:   NSButton!
    @IBOutlet weak var timeLast3Month:  NSButton!
    @IBOutlet weak var timeDateRange:   NSButton!
    
    @IBOutlet weak var timeStartDatePicker: NSDatePicker!
    @IBOutlet weak var timeEndDatePicker: NSDatePicker!
    
    @IBOutlet weak var modalityCR: NSButton!
    @IBOutlet weak var modalityCT: NSButton!
    @IBOutlet weak var modalityMG: NSButton!
    @IBOutlet weak var modalityXA: NSButton!
    @IBOutlet weak var modalityRF: NSButton!
    @IBOutlet weak var modalityNM: NSButton!
    @IBOutlet weak var modalityDX: NSButton!
    @IBOutlet weak var modalityES: NSButton!
    @IBOutlet weak var modalityPT: NSButton!
    @IBOutlet weak var modalitySR: NSButton!
    @IBOutlet weak var modalitySC: NSButton!
    @IBOutlet weak var modalityMR: NSButton!
    @IBOutlet weak var modalityAU: NSButton!
    @IBOutlet weak var modalityOT: NSButton!
    @IBOutlet weak var modalityRG: NSButton!
    @IBOutlet weak var modalityDR: NSButton!
    @IBOutlet weak var modalityXC: NSButton!
    @IBOutlet weak var modalityVL: NSButton!
    @IBOutlet weak var modalityUS: NSButton!

    @IBOutlet weak var listColumns: NSView!

    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    @IBAction func query(_ sender: Any) {
        let dataset = DataSet()
        
        dataset.prefixHeader = false
        
        // default values
        _ = dataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = dataset.set(value: "", forTagName: "PatientID")
        _ = dataset.set(value: "", forTagName: "PatientName")
        _ = dataset.set(value: "", forTagName: "PatientBirthDate")
        _ = dataset.set(value: "", forTagName: "AccessionNumber")
        _ = dataset.set(value: "", forTagName: "NumberOfStudyRelatedInstances")
        _ = dataset.set(value: self.modalitiesInStudy(), forTagName: "ModalitiesInStudy")
        _ = dataset.set(value: "", forTagName: "StudyDescription")
        _ = dataset.set(value: "", forTagName: "StudyInstanceUID")
        _ = dataset.set(value: self.studyDate(), forTagName: "StudyDate")
        _ = dataset.set(value: self.studyTime(), forTagName: "StudyTime")
        
        if searchTextField.stringValue.count > 0 {
            if searchPopUpButton.selectedTag() == 0 {
                _ = dataset.set(value: searchTextField.stringValue, forTagName: "PatientName")
            }
            else if searchPopUpButton.selectedTag() == 1 {
                _ = dataset.set(value: searchTextField.stringValue, forTagName: "PatientID")
            }
            else if searchPopUpButton.selectedTag() == 2 {
                _ = dataset.set(value: searchTextField.stringValue, forTagName: "StudyDescription")
            }
            else if searchPopUpButton.selectedTag() == 3 {
                _ = dataset.set(value: searchTextField.stringValue, forTagName: "AccessionNumber")
            }
        }



        NotificationCenter.default.post(name: .queryDidChange, object: dataset)
    }
    
    
    
    @IBAction func timeChanged(_ sender: Any) {
        var timeRadios:[NSButton] = allTimeRadios()
        
        if let button = sender as? NSButton {
            timeRadios.remove(at: timeRadios.firstIndex(of: button)!)
            button.state = .on
            
            self.timeStartDatePicker.isEnabled  = button == timeDateRange
            self.timeEndDatePicker.isEnabled    = button == timeDateRange
        }
        
        for b in timeRadios {
            b.state = .off
        }
        
        
    }
    
    
    private func studyDate() -> String {
        var string = ""
        let timeRadios:[NSButton] = allTimeRadios()
        
        for b in timeRadios {
            if b.state == .on {
                if b == timeAllDate {
                    string = ""
                }
                else if b == timeTodayAM {
                    
                }
                else if b == timeTodayPM {
                    
                }
                else if b == timeToday {
                    string = DateRange(start: Date(),
                                       end: nil,
                                       range: .after, type: DicomConstants.VR.DA).description
                }
                else if b == timeYesterday {
                    string = DateRange(start: Date().dayBefore,
                                       end: Date().dayBefore,
                                       range: .between, type: DicomConstants.VR.DA).description
                }
                else if b == timeLast2Days {
                    let sd = Calendar.current.date(byAdding: .day, value: -2, to: Date())
                    string = DateRange(start: sd,
                                       end: Date(),
                                       range: .between, type: DicomConstants.VR.DA).description
                }
                else if b == timeLast7Days {
                    let sd = Calendar.current.date(byAdding: .day, value: -7, to: Date())
                    string = DateRange(start: sd,
                                       end: Date(),
                                       range: .between, type: DicomConstants.VR.DA).description
                }
                else if b == timeLastMonth {
                    let sd = Calendar.current.date(byAdding: .month, value: -1, to: Date())
                    string = DateRange(start: sd,
                                       end: Date(),
                                       range: .between, type: DicomConstants.VR.DA).description
                }
                else if b == timeLast3Month {
                    let sd = Calendar.current.date(byAdding: .month, value: -3, to: Date())
                    string = DateRange(start: sd,
                                       end: Date(),
                                       range: .between, type: DicomConstants.VR.DA).description
                }
                else if b == timeDateRange {
                    string = DateRange(start: self.timeStartDatePicker.dateValue,
                                       end: self.timeEndDatePicker.dateValue,
                                       range: .between, type: DicomConstants.VR.DA).description
                }
            }
        }
        
        return string
    }
    
    
    private func studyTime() -> String {
        var string = ""
        let timeRadios:[NSButton] = allTimeRadios()
        
        for b in timeRadios {
            if b.state == .on {
                if b == timeAllDate {
                    string = ""
                }
                else if b == timeTodayAM {
                    
                }
                else if b == timeTodayPM {
                    
                }
                else if b == timeToday {

                }
                else if b == timeYesterday {
                    
                }
                else if b == timeLast2Days {
                    
                }
                else if b == timeLast7Days {
                    
                }
                else if b == timeLastMonth {
                    
                }
                else if b == timeLast3Month {
                    
                }
                else if b == timeDateRange {
                    
                }
            }
        }
        
        return string
    }
    
    
    private func modalitiesInStudy() -> String {
        var comps:[String] = []

        let modalityCheckBoxes:[NSButton] = allModalityCheckBoxes()
        
        for b in modalityCheckBoxes {
            if b.state == .on {
                comps.append(b.title)
            }
        }
        
        return comps.joined(separator: "\\")
    }
    
    
    
    private func allModalityCheckBoxes() -> [NSButton] {
        return [
        modalityCR,
        modalityCT,
        modalityMG,
        modalityXA,
        modalityRF,
        modalityNM,
        modalityDX,
        modalityES,
        modalityPT,
        modalitySR,
        modalitySC,
        modalityMR,
        modalityAU,
        modalityOT,
        modalityRG,
        modalityDR,
        modalityXC,
        modalityVL,
        modalityUS
        ]
    }
    
    
    private func allTimeRadios() -> [NSButton] {
        return [
            timeAllDate,
            timeTodayAM,
            timeTodayPM,
            timeToday,
            timeYesterday,
            timeLast2Days,
            timeLast7Days,
            timeLastMonth,
            timeLast3Month,
            timeDateRange
        ]
    }
}
