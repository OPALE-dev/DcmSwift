//
//  DicomInputStream.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 10/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation

public class DicomInputStream: OffsetInputStream {
    private var dataset:DataSet!
    
    public var hasPreamble:Bool         = false
    public var vrMethod:VRMethod        = .Explicit
    public var byteOrder:ByteOrder      = .LittleEndian
    public var limits                   = DicomReadLimits()
    public var bulkDataLoadingPolicy    = DICOMBulkDataLoadingPolicy.eager

    private var decodedElementCount     = 0
    private var decodedItemCount        = 0
    private var decodedFragmentCount    = 0
    private var sequenceDepth           = 0
    /// The next element is the first after the File Meta Information:
    /// files labelled Explicit VR but encoded Implicit VR are detected there.
    private var checksImplicitVR        = false
    /// Set when that detection switched the data set to Implicit VR.
    private var detectedImplicitVR      = false
    
    /**
     Init a DicomInputStream with a file path
     */
    public override init(filePath:String) {
        super.init(filePath: filePath)
        dataset = DataSet()
    }
    
    /**
    Init a DicomInputStream with a file URL
    */
    public override init(url:URL) {
        super.init(url: url)
        dataset = DataSet()
    }
    
    /**
    Init a DicomInputStream with a Data object
    */
    public override init(data:Data) {
        super.init(data: data)
        dataset = DataSet()
    }
    
    
    // MARK: -
    /**
     Reads a data set from the stream.
     
     - Parameters:
        - headerOnly: only read the header. Default is set to false
        - withoutPixelData: avoid reading the pixel data
        - enforceVR: reject invalid explicit Value Representation codes
     - Throws: StreamError.notDicomFile, StreamError.cannotReadStream
     - Returns: the `DataSet` read from the stream
     */
    public func readDataset(headerOnly:Bool = false, withoutPixelData:Bool = false, enforceVR:Bool = true) throws -> DataSet? {
        if stream == nil {
            throw StreamError.cannotOpenStream(message: "Cannot open stream, init failed")
        }
                
        self.open()
        defer { self.close() }
        decodedElementCount = 0
        decodedItemCount = 0
        decodedFragmentCount = 0
        sequenceDepth = 0
        
        // try to read 128 00H + DCIM magic world
        let preambleData = read(length: 132)
        
        // A Part 10 file: any 128-byte preamble (PS3.10 7.1 leaves its content
        // to the application, e.g. a TIFF header), then "DICM".
        let isPart10 = preambleData.map { $0.count == 132 && $0.suffix(4).elementsEqual(Array("DICM".utf8)) } ?? false
        if !isPart10 {
            // print("no DCIM preamble found, try to read dataset anyway")
            hasPreamble = false
            
        } else {
            // try to read DCIM magic word
            guard let magicData = preambleData?.dropFirst(128) else {
                throw StreamError.cannotReadStream(message: "Cannot read DICOM magic bytes (DICM)")
            }
            
            guard let magicWord = String(bytes: magicData, encoding: .ascii),
                  magicWord == DicomConstants.dicomMagicWord else {
                throw StreamError.notDicomFile(message: "Not a DICOM file, no DICM magic bytes found")
            }
            
            hasPreamble = true
        }
        
        // enforce vr Method
        if hasPreamble {
            // we kill the 00000000 not-a-tag read earlier
            // tag = nil
            // we will parse the DICOM meta Info header as Explicit VR
            vrMethod = .Explicit
        } else {
            if enforceVR == true {
                // A data set without File Meta Information: Implicit VR
                // Little Endian (the default, and old ACR-NEMA files) unless
                // the first element carries a VR code, and Big Endian when
                // its group reads that way (e.g. 00 08 for 0008).
                let head = [UInt8](preambleData?.prefix(6) ?? Data())
                let explicitVR = head.count == 6 && head[4...5].allSatisfy({ (0x41...0x5A).contains($0) })
                    && DicomSpec.vr(for: String(decoding: head[4...5], as: UTF8.self)) != nil
                if explicitVR {
                    let bigEndian = head[0] == 0 && head[1] != 0
                    byteOrder = bigEndian ? .BigEndian : .LittleEndian
                    dataset.transferSyntax = TransferSyntax(
                        bigEndian ? TransferSyntax.explicitVRBigEndian : TransferSyntax.explicitVRLittleEndian)
                    vrMethod = .Explicit
                } else {
                    dataset.transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian)
                    vrMethod = .Implicit
                }
            }
            
            // reset stream and offset using backstream
            backstream.open()
            
            stream = backstream
            offset = 0
        }
                                
        // preambule processing is done
        dataset.hasPreamble = hasPreamble
        if hasPreamble, let preambleData, preambleData.prefix(128).contains(where: { $0 != 0 }) {
            dataset.preamble = preambleData.prefix(128)
        }
        dataset.vrMethod = vrMethod
        dataset.byteOrder = byteOrder
        var fileMetaEndOffset: Int? = nil
        var shouldInflateDataSet = false
    
        // read elements to fill the dataset
        while(stream.hasBytesAvailable && offset < total && !dataset.isCorrupted) {
            // Fewer bytes than a tag: trailing padding, ignored.
            if total - offset < 4 { break }
            let elementStart = offset
            var order = byteOrder
            checksImplicitVR = hasPreamble && vrMethod == .Explicit && !shouldInflateDataSet
                && fileMetaEndOffset == offset
            
            // The group length excludes the 12-byte (0002,0000) element itself.
            // Until it is known, the first Part 10 element is always Little Endian.
            if hasPreamble && (fileMetaEndOffset == nil || offset < fileMetaEndOffset!) {
                order = .LittleEndian
            }
            
            let readElement = readDataElement(dataset: dataset, parent: nil, vrMethod: vrMethod, order: order)
            checksImplicitVR = false
            if detectedImplicitVR {
                detectedImplicitVR = false
                vrMethod = .Implicit
                dataset.vrMethod = .Implicit
            }
            if let newElement = readElement {
                // header only option
                if headerOnly && newElement.tag.group != DicomConstants.metaInformationGroup {
                    break
                }
                
                // without pixel data option
                if !headerOnly && withoutPixelData && newElement.tagCode() == "7fe00010" {
                    break
                }
                
                // grab the file Meta Information Group Length
                // theorically used to determine the end of the Meta Info Header
                // but we rely on 0002 group to really check this for now
                if newElement.name == "FileMetaInformationGroupLength" {
                    if let length = newElement.value as? UInt32 {
                        dataset.fileMetaInformationGroupLength = Int(length)
                        fileMetaEndOffset = newElement.endOffset + Int(length)
                    }
                }
                
                // determine file transfer syntax (used later to read the actual dataset part of the DICOM attributes)
                if newElement.name == "TransferSyntaxUID" {
                    vrMethod  = .Explicit
                    byteOrder = .LittleEndian
                    
                    guard let uid = newElement.value as? String,
                          let syntax = TransferSyntax(uid),
                          syntax.capability.canReadDataset else {
                        let uid = (newElement.value as? String) ?? ""
                        throw StreamError.unsupportedTransferSyntax(uid: uid)
                    }
                    dataset.transferSyntax = syntax
                    vrMethod = syntax.vrMethod
                    byteOrder = syntax.byteOrder
                    shouldInflateDataSet = TransferSyntax.deflatesDataSet(uid)
                    
                    // update the dataset properties
                    dataset.vrMethod = vrMethod
                    dataset.byteOrder = byteOrder
                }
                                                            
                // append element to sub-datasets, if everything is OK
                if !dataset.isCorrupted {
                    dataset.add(element: newElement)

                    if shouldInflateDataSet,
                       let fileMetaEndOffset,
                       offset == fileMetaEndOffset {
                        guard let compressed = read(length: readableBytes) else {
                            throw StreamError.cannotReadStream(message: "Cannot read deflated Data Set")
                        }
                        let inflated = try DICOMDeflate.decompress(
                            compressed,
                            maximumOutputLength: limits.maximumInflatedDataSetLength
                        )
                        let inflatedStream = DicomInputStream(data: inflated)
                        inflatedStream.limits = limits
                        guard let inflatedDataSet = try inflatedStream.readDataset(enforceVR: false) else {
                            throw StreamError.cannotReadStream(message: "Cannot parse inflated Data Set")
                        }
                        for inflatedElement in inflatedDataSet.datasetElements {
                            dataset.add(element: inflatedElement)
                        }
                        break
                    }
                    
                } else {
                    throw StreamError.datasetIsCorrupted(message: "Dataset is corrupted")
                }
            } else if offset <= elementStart {
                // Nothing could be read: stop instead of retrying forever.
                throw StreamError.datasetIsCorrupted(message: "Unreadable data element at offset \(elementStart)")
            }
        }

        if dataset.isCorrupted {
            throw StreamError.datasetIsCorrupted(message: "Dataset is corrupted")
        }
        
        dataset.sortElements()
        
        return dataset
    }
    


    
    // MARK: -
    /**
     Tries to reads a `DataTag` with a given byte order
     
     - Parameter order: the byte order to read the stream to
     - Returns: the `DataTag` read from the stream, or `nil` on failure
     */
    private func readDataTag(order:ByteOrder = .LittleEndian) -> DataTag? {
        return DataTag(withStream: self, byteOrder:order)
    }
    
    /**
     Tries to reads a Value Representation
     
     If the data element has an explicit VR, the stream can read the VR. If the VR is implicit, it
     means the stream does not contains the VR, but we can catch the VR with the data element tag, that's
     why the data element is provided in the parameters
     
     - Parameters:
        - element: the data element to get the tag (and thus the vr)
        - vrMethod: is the VR explicit (written in the data) or implicit (not written in the data) ?
     - Returns: the value representation of the element, or nil
     */
    private func readVR(element:DataElement, vrMethod:VRMethod = .Explicit, prefetched:Data? = nil) -> VR.VR? {
        var vr:VR.VR? = nil
        
        if vrMethod == .Explicit {
            guard let data = prefetched ?? self.read(length: 2) else {
                return nil
            }

            guard let explicitVR = DicomSpec.vr(for: data.toString()) else {
                return nil
            }
            vr = explicitVR
        }
        else {
            // PS3.5 7.8.1 assigns LO to Private Creator Data Elements even
            // though their tags are not part of the public data dictionary.
            vr = element.tag.isPrivateCreator
                ? .LO
                : DicomSpec.shared.vrForTag(withCode: element.tagCode())
            let candidates = DicomSpec.shared.vrsForTag(withCode: element.tagCode())
            if candidates.count > 1 {
                if candidates.contains(.OW), !candidates.contains(.SS) {
                    // Pixel Data and other OB/OW data are OW in Implicit VR
                    // (PS3.5 A.1).
                    vr = .OW
                } else {
                    // US or SS (or OW) follows Pixel Representation (0028,0103).
                    let signed = element.dataset?.allElements.last(where: { $0.tagCode() == "00280103" })
                        .flatMap { $0.data.count >= 2 ? $0.data.toUInt16(byteOrder: $0.byteOrder) : nil } == 1
                    vr = signed ? .SS : .US
                }
            }
        }
        
        if element.element == "0000" {
            vr = .UL
        }
        
        if vr == nil {
            vr = .UN
        }
        
        if     vr == .SQ ||
               vr == .OB ||
               vr == .OD ||
               vr == .OL ||
               vr == .OV ||
               vr == .OW ||
               vr == .OF ||
               vr == .SQ ||
               vr == .SV ||
               vr == .UC ||
               vr == .UT ||
               vr == .UN ||
               vr == .UR ||
               vr == .UV {
            // Long-form Explicit VR headers contain two reserved zero bytes.
            if vrMethod == .Explicit {
                guard read(length: 2) == Data([0x00, 0x00]) else { return nil }
            }
        }
        
        return vr!
    }
    
    /**
     Reads the length of a data element
     
     - Parameters:
        - vrMethod: is the VR explicit (written in the data) or implicit (not written in the data) ?
        - vr: the VR of the data element the length belongs to
        - order: the byte order of the length bytes
     - Returns: the length of a data element
     */
    private func readLength(
        vrMethod:VRMethod = .Explicit,
        vr:VR.VR,
        order:ByteOrder = .LittleEndian
    ) -> Int? {
        let usesLongLength = vr == .SQ || vr == .OB || vr == .OD || vr == .OF ||
            vr == .OL || vr == .OV || vr == .OW || vr == .SV || vr == .UC ||
            vr == .UN || vr == .UR || vr == .UT || vr == .UV

        if vrMethod == .Explicit {
            if usesLongLength {
                guard let bytes = read(length: 4) else { return nil }
                let value = bytes.toUInt32(byteOrder: order)
                return value == UInt32.max ? -1 : Int(value)
            } else {
                guard let bytes = read(length: 2) else { return nil }
                return Int(bytes.toUInt16(byteOrder: order))
            }
        } else {
            guard let bytes = read(length: 4) else { return nil }
            let value = bytes.toUInt32(byteOrder: order)
            return value == UInt32.max ? -1 : Int(value)
        }
    }
    

    /**
     Tries to read a value of a `DataElement`.
     
     - Parameter length: the length of the value
     - Returns: The value as `Data`
     */
    private func readValue(length:Int) -> Data? {
        if length > 0 && (offset + length <= total) {
            return read(length: length)
        }
        
        return nil
    }

    private func read32BitLength(byteOrder: ByteOrder) -> Int? {
        guard let bytes = read(length: 4) else { return nil }
        let value = bytes.toUInt32(byteOrder: byteOrder)
        return value == UInt32.max ? -1 : Int(value)
    }
    
    
    
    private func readError(forLength length:Int, element: DataElement, message:String) -> DataElement {
        let v = ValidationResult(element, message: message, severity: .Fatal)
                
        dataset.internalValidations.append(v)
        dataset.isCorrupted = true
        
        Logger.error(message)
        
        return element
    }
    
    
    /**
     Tries to read a data element from the stream
     
     - Parameters:
        - dataset:
        - parent:
        - vrMethod:
        - order:
        - inTag:
     - Returns: the data element read on success, or nil on failure
     */
    private func readDataElement(
        dataset:DataSet?                    = nil,
        parent:DataElement?                 = nil,
        vrMethod:VRMethod    = .Explicit,
        order:ByteOrder      = .LittleEndian,
        inTag:DataTag?                      = nil
    ) -> DataElement? {
        let startOffset = offset
        
        // we try to read the tag only if no `inTag` given
        guard let tag = inTag ?? readDataTag(order: order) else {
            Logger.error("Cannot read tag at offset at \(offset)")
            return nil
        }
                
        // ignore delimitation items
        if tag.code == "fffee0dd" {
            return nil
        }
        else if tag.code == "fffee00d" {
            return nil
        }
                                
        var element = DataElement(withTag:tag, dataset: dataset, parent: parent)
        element.characterSet = (parent as? DataItem)?.effectiveCharacterSet ?? dataset?.characterSet
        decodedElementCount += 1
        if decodedElementCount > limits.maximumElementCount {
            return readError(
                forLength: 0,
                element: element,
                message: "Fatal, maximum Data Element count exceeded (\(limits.maximumElementCount))"
            )
        }
        
        element.startOffset     = startOffset
        
        // enforce Explicit for group 0002 (Meta Info Header)
        element.vrMethod        = element.group == "0002" ? .Explicit : vrMethod
        
        // enforce Little Endian for group 0002 (Meta Info Header)
        element.byteOrder       = element.group == "0002" ? .LittleEndian : order
        element.vrOffset        = offset
        
        // Some writers label Implicit VR data sets as Explicit VR: when the
        // first element after the File Meta Information has no VR code, its
        // bytes start a 32-bit length (pydicom and DCMTK read such files the
        // same way).
        var prefetchedVR: Data?
        var headerRead = false
        if checksImplicitVR, element.group != "0002", element.vrMethod == .Explicit {
            guard let vrBytes = read(length: 2) else {
                return readError(forLength: 0, element: element, message: "Fatal, truncated header for \(tag)")
            }
            if vrBytes.allSatisfy({ (0x41...0x5A).contains($0) }), DicomSpec.vr(for: vrBytes.toString()) != nil {
                prefetchedVR = vrBytes
            } else {
                guard let rest = read(length: 2) else {
                    return readError(forLength: 0, element: element, message: "Fatal, truncated header for \(tag)")
                }
                let bytes = [UInt8](vrBytes + rest)
                let length = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
                Logger.warning("The data set is labelled Explicit VR but encoded in Implicit VR; reading it as Implicit VR")
                detectedImplicitVR = true
                self.vrMethod = .Implicit
                element.vrMethod = .Implicit
                element.vr = readVR(element: element, vrMethod: .Implicit) ?? .UN
                element.lengthOffset = offset - 4
                element.length = length == 0xFFFF_FFFF ? -1 : Int(length)
                headerRead = true
            }
        }

        if !headerRead {
            guard let vr = readVR(element:element, vrMethod: element.vrMethod, prefetched: prefetchedVR) else {
                let message = "Fatal, invalid or truncated Explicit VR header for \(tag) at offset \(element.vrOffset)"
                return readError(forLength: 0, element: element, message: message)
            }
            element.vr              = vr
            element.lengthOffset    = offset
            guard let decodedLength = readLength(vrMethod: element.vrMethod, vr: element.vr, order: element.byteOrder) else {
                let message = "Fatal, truncated value length for \(tag) at offset \(offset)"
                return readError(forLength: 0, element: element, message: message)
            }
            element.length          = decodedLength
        }
        element.dataOffset      = offset
        // Encapsulated Pixel Data is OB (PS3.5 A.4), whatever Implicit VR
        // suggested.
        if element.tagCode() == "7fe00010", element.length == -1, element.vr == .OW, element.vrMethod == .Implicit {
            element.vr = .OB
        }
        
        
        // check for invalid length
        if element.length < -1 {
            let message = "Fatal, invalid negative length for \(tag) at offset \(element.lengthOffset)"
            return readError(forLength: element.length, element: element, message: message)
        }
        if element.length > limits.maximumElementValueLength {
            let message = "Fatal, value length for \(tag) exceeds configured maximum (\(element.length) > \(limits.maximumElementValueLength))"
            return readError(forLength: element.length, element: element, message: message)
        }
        if element.length > readableBytes {
            let message = "Fatal, cannot read length properly, decoded \(tag) length at offset(\(offset-4)) overflows (\(element.length))"
            return readError(forLength: element.length, element: element, message: message)
        }
        
        // read value data
        // if OB/OW but not in prefix header
        if tag.group != "0002" && (element.vr == .OW || element.vr == .OB) {
            if element.name == "PixelData" && element.length == -1 {
                guard let sequence = readPixelSequence(tag: tag, byteOrder: order) else {
                    Logger.error("Cannot read Pixel Sequence \(tag) at \(offset)")
                    return nil
                }
                
                sequence.parent         = element
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                sequence.lengthOffset   = element.lengthOffset
                sequence.vrOffset       = element.vrOffset
                element                 = sequence

            } else if element.length == 0 {
                element.data = Data()
            } else {
                guard readValue(for: element) else { return nil }
            }
        }
        else if element.vr == .SQ || (element.vr == .UN && element.length == -1) {
            // An UN element of undefined length (or an unknown one in Implicit
            // VR) holds a Sequence in Implicit VR Little Endian (PS3.5 6.2.2).
            let isUnknownSequence = element.vr == .UN
            let savedVRMethod = self.vrMethod
            if isUnknownSequence { self.vrMethod = .Implicit }
            let read = readDataSequence(
                tag: element.tag,
                length: Int(element.length),
                byteOrder: isUnknownSequence ? .LittleEndian : order,
                parent: parent
            )
            self.vrMethod = savedVRMethod
            guard let sequence = read else {
                Logger.error("Cannot read Sequence \(tag) at \(self.offset)")
                return nil
            }
                        
            sequence.parent         = element
            sequence.vr             = .SQ
            sequence.vrMethod       = isUnknownSequence ? .Implicit : element.vrMethod
            sequence.startOffset    = element.startOffset
            sequence.dataOffset     = element.dataOffset
            sequence.lengthOffset   = element.lengthOffset
            sequence.vrOffset       = element.vrOffset
            sequence.length         = element.length
            element                 = sequence
        }
        else if element.length == 0 {
            element.data = Data()
        }
        else {
            guard readValue(for: element) else { return nil }
        }
        
        element.endOffset = offset

        if element.tag.isPrivateDataElement {
            element.privateCreator = privateCreator(for: element, parent: parent, dataset: dataset)
        }
        if element.name == "SpecificCharacterSet", let item = parent as? DataItem {
            item.characterSet = DICOMCharacterSet(specificCharacterSet: element.data.toString())
        }
        
        //print("element \(element)")
                        
        return element
    }

    private func readValue(for element:DataElement) -> Bool {
        if case .lazy(let minimumLength) = bulkDataLoadingPolicy,
           minimumLength >= 0,
           element.length >= minimumLength,
           isBulkDataVR(element.vr),
           let sourceURL {
            element.deferData(to: DICOMBulkDataReference(
                url: sourceURL,
                offset: offset,
                length: element.length
            ))
            return skip(length: element.length)
        }

        guard let value = readValue(length: element.length) else { return false }
        element.data = value
        return true
    }

    private func isBulkDataVR(_ vr:VR.VR) -> Bool {
        switch vr {
        case .OB, .OD, .OF, .OL, .OV, .OW, .UN: return true
        default: return false
        }
    }

    private func privateCreator(
        for element: DataElement,
        parent: DataElement?,
        dataset: DataSet?
    ) -> String? {
        guard let creatorElement = element.tag.privateCreatorElement else { return nil }
        let siblings: [DataElement]
        if let item = parent as? DataItem {
            siblings = item.elements
        } else {
            siblings = dataset?.allElements ?? []
        }

        guard let reservation = siblings.last(where: {
            $0.group.lowercased() == element.group.lowercased() &&
            $0.element.lowercased() == creatorElement
        }), reservation.tag.isPrivateCreator, let data = reservation.data else {
            return nil
        }

        return DICOMCharacterSet.defaultRepertoire.decode(data)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }
    
    
    
    /**
     Tries to read a sequence (SQ) from the stream
     
     - Remark: why provide the length when the parent data element has it ? same for the tag, same for the byte order
     
     - Parameters:
        - tag: the tag of the sequence
        - length: length of the sequence
        - byteOrder: byte order of the sequence
        - parent: the data element containing the sequence
     - Returns: the data sequence read
     */
    private func readDataSequence(
        tag:DataTag,
        length:Int,
        byteOrder:ByteOrder,
        parent: DataElement? = nil
    ) -> DataSequence? {
        let sequence:DataSequence = DataSequence(withTag:tag, parent: parent)
        guard sequenceDepth < limits.maximumSequenceDepth else {
            let message = "Fatal, maximum Sequence nesting depth exceeded (\(limits.maximumSequenceDepth))"
            return readError(forLength: length, element: sequence, message: message) as? DataSequence
        }
        sequenceDepth += 1
        defer { sequenceDepth -= 1 }

        func fail(_ message: String, length: Int = 0) -> Bool {
            _ = readError(forLength: length, element: sequence, message: message)
            return false
        }

        func consumeDelimiter(_ name: String) -> Bool {
            guard let delimiterLength = read32BitLength(byteOrder: byteOrder) else {
                return fail("Fatal, truncated \(name) length")
            }
            guard delimiterLength == 0 else {
                return fail("Fatal, \(name) length must be zero (\(delimiterLength))", length: delimiterLength)
            }
            return true
        }

        func readItem(_ itemTag: DataTag, itemLength: Int, enclosingEnd: Int?) -> Bool {
            guard itemTag.code == "fffee000" else {
                return fail("Fatal, expected Item tag in Sequence but found \(itemTag)")
            }
            guard itemLength >= -1 else {
                return fail("Fatal, invalid negative Item length (\(itemLength))", length: itemLength)
            }
            guard itemLength == -1 || itemLength <= limits.maximumElementValueLength else {
                return fail("Fatal, Item length exceeds configured maximum (\(itemLength) > \(limits.maximumElementValueLength))", length: itemLength)
            }

            decodedItemCount += 1
            guard decodedItemCount <= limits.maximumItemCount else {
                return fail("Fatal, maximum Sequence Item count exceeded (\(limits.maximumItemCount))", length: itemLength)
            }

            let item = DataItem(withTag: itemTag, parent: sequence)
            item.characterSet = (sequence.parent as? DataItem)?.effectiveCharacterSet
                ?? self.dataset.characterSet
            item.length = itemLength
            item.startOffset = offset - 8
            item.dataOffset = offset
            item.vrMethod = .Implicit
            sequence.items.append(item)

            if itemLength == -1 {
                while true {
                    guard let tagData = read(length: 4) else {
                        return fail("Fatal, truncated undefined-length Item")
                    }
                    let nestedTag = DataTag(withData: tagData, byteOrder: byteOrder)
                    if nestedTag.code == "fffee00d" {
                        guard consumeDelimiter("Item Delimitation Item") else { return false }
                        break
                    }
                    if nestedTag.code == "fffee0dd" {
                        return fail("Fatal, Sequence Delimitation Item found before Item Delimitation Item")
                    }
                    guard let element = readDataElement(
                        dataset: self.dataset,
                        parent: item,
                        vrMethod: vrMethod,
                        order: byteOrder,
                        inTag: nestedTag
                    ) else {
                        return fail("Fatal, cannot read Data Element in undefined-length Item")
                    }
                    item.elements.append(element)
                }
            } else {
                guard itemLength <= readableBytes else {
                    return fail("Fatal, Item length overflows the remaining stream", length: itemLength)
                }
                let itemEnd = offset + itemLength
                if let enclosingEnd, itemEnd > enclosingEnd {
                    return fail("Fatal, Item length exceeds its enclosing Sequence", length: itemLength)
                }
                while offset < itemEnd {
                    let previousOffset = offset
                    guard let element = readDataElement(
                        dataset: self.dataset,
                        parent: item,
                        vrMethod: vrMethod,
                        order: byteOrder
                    ) else {
                        return fail("Fatal, cannot read Data Element in defined-length Item")
                    }
                    guard offset > previousOffset, offset <= itemEnd else {
                        return fail("Fatal, Data Element crosses the defined Item boundary")
                    }
                    item.elements.append(element)
                }
            }

            item.endOffset = offset
            return true
        }

        if length >= 0 {
            guard length <= readableBytes else {
                return readError(forLength: length, element: sequence, message: "Fatal, Sequence length overflows the remaining stream") as? DataSequence
            }
            let sequenceEnd = offset + length
            while offset < sequenceEnd {
                guard sequenceEnd - offset >= 8,
                      let itemTagData = read(length: 4),
                      let itemLength = read32BitLength(byteOrder: byteOrder) else {
                    _ = fail("Fatal, truncated Item header in defined-length Sequence")
                    return sequence
                }
                let itemTag = DataTag(withData: itemTagData, byteOrder: byteOrder)
                guard readItem(itemTag, itemLength: itemLength, enclosingEnd: sequenceEnd) else { return sequence }
            }
            if offset != sequenceEnd {
                _ = fail("Fatal, Sequence content does not match its defined length")
            }
        } else if length == -1 {
            sequence.vrMethod = .Implicit
            while true {
                guard let itemTagData = read(length: 4) else {
                    _ = fail("Fatal, missing Sequence Delimitation Item")
                    return sequence
                }
                let itemTag = DataTag(withData: itemTagData, byteOrder: byteOrder)
                if itemTag.code == "fffee0dd" {
                    guard consumeDelimiter("Sequence Delimitation Item") else { return sequence }
                    break
                }
                guard let itemLength = read32BitLength(byteOrder: byteOrder) else {
                    _ = fail("Fatal, truncated Item length in undefined-length Sequence")
                    return sequence
                }
                guard readItem(itemTag, itemLength: itemLength, enclosingEnd: nil) else { return sequence }
            }
        }
        
        sequence.endOffset = offset
                
        return sequence
    }
    
    
    // Unused by now..
    /// Returns nil
    private func readItem(
        length:Int,
        byteOrder:ByteOrder,
        parent: DataElement? = nil
    ) -> DataItem? {
        return nil
    }
    
    
    /**
     Tries to read a pixel sequence from a stream.
     
     - Remark: why provide the tag, knowing the pixel data always have the same tag, which is (fffee,0dd)
     
     - Parameters:
        - tag: the tag of the pixel sequence
        - byteOrder: how to read the pixel data
     - Returns: the pixel sequence read
     */
    private func readPixelSequence(tag:DataTag, byteOrder:ByteOrder) -> PixelSequence? {
        let pixelSequence = PixelSequence(withTag: tag)
        
        // read item tag
        guard let firstItemTagData = read(length: 4) else { return nil }
        var itemTag = DataTag(withData: firstItemTagData, byteOrder: byteOrder)
        var isOffsetTable = true

        while true {
            if itemTag.code == "fffee0dd" {
                guard let delimiterLength = read32BitLength(byteOrder: byteOrder),
                      delimiterLength == 0 else {
                    let message = "Fatal, invalid Pixel Data Sequence Delimitation Item"
                    return readError(forLength: 0, element: pixelSequence, message: message) as? PixelSequence
                }
                break
            }
            guard itemTag.code == "fffee000" else {
                let message = "Fatal, unexpected tag \(itemTag) in encapsulated Pixel Data"
                return readError(forLength: 0, element: pixelSequence, message: message) as? PixelSequence
            }
            if !isOffsetTable {
                decodedFragmentCount += 1
                if decodedFragmentCount > limits.maximumPixelFragmentCount {
                    let message = "Fatal, maximum Pixel Data fragment count exceeded (\(limits.maximumPixelFragmentCount))"
                    return readError(forLength: 0, element: pixelSequence, message: message) as? PixelSequence
                }
            }
            // create item
            let item            = DataItem(withTag: itemTag)
            item.startOffset    = offset - 4
            item.vrMethod       = .Explicit
            
            // read item length
            guard let itemLength = read32BitLength(byteOrder: byteOrder) else { return nil }
            if itemLength < 0 {
                let message = "Fatal, encapsulated Pixel Data items require defined lengths"
                return readError(forLength: itemLength, element: pixelSequence, message: message) as? PixelSequence
            }

            item.dataOffset = offset
                                    
            // check for invalid lengths
            if itemLength > readableBytes {
                let message = "Fatal, cannot read PixelSequence item length properly, decoded length at offset(\(offset-4)) overflows (\(itemLength))"
                return readError(forLength: itemLength, element: pixelSequence, message: message) as? PixelSequence
            }
            
            item.length = itemLength
            
            if itemLength > 0 {
                guard readValue(for: item) else { return nil }
            }
            item.endOffset = offset
            
            pixelSequence.items.append(item)
            isOffsetTable = false
            
            // read next again
            guard let nextItemTagData = read(length: 4) else { return nil }
            itemTag = DataTag(withData: nextItemTagData, byteOrder: byteOrder)
        }
        
        return pixelSequence
    }
}
