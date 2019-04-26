//
//  ImageViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 22/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class ImageViewController: NSViewController {
    @IBOutlet weak var imageView: NSImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector: #selector(dataSelectionDidChange(n:)), name: .dataSelectionDidChange, object: nil)
        
        self.imageView.wantsLayer = true
        self.imageView.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    @objc func dataSelectionDidChange(n:Notification) {
        if let managedObject = n.object as? NSManagedObject {
            var instance:Instance!
            
            if let patient = managedObject as? Patient {
                if let st = patient.studies?.allObjects.first as? Study {
                    if let se = st.series?.allObjects.first as? Serie {
                        if let i = se.instances?.allObjects.first as? Instance {
                            instance = i
                        }
                    }
                }
            }
            else if let study = managedObject as? Study {
                if let se = study.series?.allObjects.first as? Serie {
                    if let i = se.instances?.allObjects.first as? Instance {
                        instance = i
                    }
                }
            }
            else if let serie = managedObject as? Serie {
                if let i = serie.instances?.allObjects.first as? Instance {
                    instance = i
                }
            }
                        
            if instance != nil {
                if let dicomFile = DicomFile(forPath: instance.filePath!) {
                    if let dicomImage = dicomFile.dicomImage {
                        self.imageView.image = dicomImage.image()
                    }
                }
            }
        }
    }
}
