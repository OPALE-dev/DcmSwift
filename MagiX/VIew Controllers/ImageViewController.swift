//
//  ImageViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 22/04/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift


class SerieProxy {
    var serie:Serie!
    
    public var images:[NSImage] = []
    
    init(serie:Serie) {
        self.serie = serie
        
        let instances = (serie.instances?.sortedArray(using: [NSSortDescriptor(key: "instanceNumber", ascending: true), NSSortDescriptor(key: "contentDate", ascending: true)]) as! [Instance] as NSArray) as! [Instance]
        
        for i in instances {
            if let dicomFile = DicomFile(forPath: i.filePath!) {
                if let dicomImage = dicomFile.dicomImage {
                    if dicomImage.isMultiframe {
                        for i in 0..<dicomImage.numberOfFrames-1 {
                            if let image = dicomImage.image(forFrame: i) {
                                images.append(image)
                            }
                        }
                    }
                    else {
                        if let image = dicomImage.image() {
                            images.append(image)
                        }
                    }
                }
            }
        }
    }
}



class ImageViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var backgroundView: NSView!
    @IBOutlet weak var imageView: NSImageView!
    
    @IBOutlet weak var imageSizeTextField: NSTextField!
    @IBOutlet weak var viewSizeTextField: NSTextField!
    @IBOutlet weak var imageNumberTextField: NSTextField!
    @IBOutlet weak var transferSyntaxTextField: NSTextField!
    
    var series:[Serie] = []
    var dicomImage:DicomImage?
    var currentSerie:Serie?
    var currentSerieProxy:SerieProxy?
    var currentIndex = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector: #selector(dataSelectionDidChange(n:)), name: .dataSelectionDidChange, object: nil)
        
        self.collectionView.allowsMultipleSelection = false
        self.collectionView.isSelectable = true
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.register(CollectionViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ImageViewCollectionitem"))
        
        self.backgroundView.wantsLayer = true
        self.backgroundView.layer?.backgroundColor = NSColor.black.cgColor
        
        self.imageView.wantsLayer = true
        self.imageView.layer?.backgroundColor = NSColor.black.cgColor
        
        _ = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            if let proxy = self.currentSerieProxy {
                
                if self.currentIndex < proxy.images.count-1 {
                    self.currentIndex += 1
                } else {
                    self.currentIndex = 0
                }
                
                if proxy.images.count > 0 {
                    self.imageView.image = proxy.images[self.currentIndex]
                    
                        self.imageNumberTextField.stringValue = "Images: \(self.currentIndex+1)/\(proxy.images.count)"
                }
            }
        }
    }
    
    @objc func dataSelectionDidChange(n:Notification) {
        if let managedObject = n.object as? NSManagedObject {
            var instance:Instance!
            
            if let study = managedObject as? Study {
                if let se = study.series?.allObjects.first as? Serie {
                    self.setCurrentSerie(se)
                    
                    if let i = se.instances?.allObjects.first as? Instance {
                        self.series = study.series?.allObjects as! [Serie]
                        instance = i
                    }
                }
            }
            else if let serie = managedObject as? Serie {
                if let i = serie.instances?.allObjects.first as? Instance {
                    self.series = [serie]
                    instance = i
                    
                    self.setCurrentSerie(serie)
                }
            }
            
            if instance != nil {
                self.collectionView.reloadData()
                self.collectionView.layoutSubtreeIfNeeded()
            }
            
        }
    }
    
    
    
    func setCurrentSerie(_ serie:Serie) {
        self.currentSerie = serie
        self.currentSerieProxy = SerieProxy(serie: serie)
        
        if let tsuid = self.currentSerie?.transferSyntaxUID {
            self.transferSyntaxTextField.stringValue = "Syntax: " + DicomSpec.shared.nameForUID(withUID: tsuid)
        }
        
        if let nbInstances = self.currentSerie?.numberOfInstances {
            self.imageNumberTextField.stringValue = "Images: \(self.currentIndex)/\(nbInstances)"
        }
    }
    
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.series.count
    }
    
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ImageViewCollectionitem"), for: indexPath)
        guard let collectionViewItem = item as? CollectionViewItem else {return item}
        let serie = self.series[indexPath.item]
        
        collectionViewItem.modalityLabel.stringValue = serie.modality ?? ""
        collectionViewItem.instancesCountLabel.stringValue = String(serie.numberOfInstances)
        
        if let data = serie.imageProxy, let image = NSImage(data: data) {
            collectionViewItem.image = image
        }
    
        return item
    }
    
    
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first else {
            return
        }
        guard let item = collectionView.item(at: indexPath as IndexPath) else {
            return
        }
        
        let serie = self.series[indexPath.item]
        
        self.setCurrentSerie(serie)

        (item as! CollectionViewItem).setHighlight(selected: true)
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first else {
            return
        }
        guard let item = collectionView.item(at: indexPath as IndexPath) else {
            return
        }
        (item as! CollectionViewItem).setHighlight(selected: false)
    }
}
