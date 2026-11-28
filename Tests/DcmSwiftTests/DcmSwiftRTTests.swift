import Foundation
import XCTest
@testable import DcmSwift

/// RT Structure Set, Dose, and Plan (PS3.3 A.18 to A.20).
final class DcmSwiftRTTests: XCTestCase {
    /// Builds Data Elements and Sequences in a data set.
    private struct Builder {
        let dataSet = DataSet()

        func element(_ name: String, _ value: Any, vr: VR.VR? = nil, in item: DataItem? = nil) {
            guard let element = DataElement(withTagName: name, dataset: dataSet, parent: item) else {
                XCTFail("unknown attribute \(name)")
                return
            }
            if let vr { element.vr = vr }
            if let data = value as? Data {
                element.data = data
                element.length = data.count
            } else {
                XCTAssertTrue(element.setValue(value), name)
            }
            if let item { item.elements.append(element) } else { dataSet.add(element: element) }
        }

        /// A Sequence with one Item per closure.
        func sequence(_ name: String, in parent: DataItem? = nil, items: [(DataItem) -> Void]) {
            let sequence = DataSequence(withTag: DicomSpec.shared.dataTag(forName: name)!, parent: parent)
            sequence.vr = .SQ
            sequence.length = -1
            for fill in items {
                let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
                item.length = -1
                sequence.items.append(item)
                fill(item)
            }
            if let parent { parent.elements.append(sequence) } else { dataSet.add(element: sequence) }
        }
    }

    func testStructureSet() throws {
        let builder = Builder()
        builder.element("SOPClassUID", "1.2.840.10008.5.1.4.1.1.481.3")
        builder.element("StructureSetLabel", "Plan")
        builder.sequence("StructureSetROISequence", items: [
            { item in
                builder.element("ROINumber", "1", in: item)
                builder.element("ROIName", "PTV", in: item)
                builder.element("ROIGenerationAlgorithm", "MANUAL", in: item)
            },
        ])
        builder.sequence("ROIContourSequence", items: [
            { item in
                builder.element("ReferencedROINumber", "1", in: item)
                builder.element("ROIDisplayColor", "255\\0\\128", in: item)
                builder.sequence("ContourSequence", in: item, items: [
                    { contour in
                        builder.element("ContourGeometricType", "CLOSED_PLANAR", in: contour)
                        builder.element("NumberOfContourPoints", "3", in: contour)
                        builder.element("ContourData", "0\\0\\5\\10\\0\\5\\0\\10\\5", in: contour)
                    },
                ])
            },
        ])
        builder.sequence("RTROIObservationsSequence", items: [
            { item in
                builder.element("ObservationNumber", "1", in: item)
                builder.element("ReferencedROINumber", "1", in: item)
                builder.element("RTROIInterpretedType", "PTV", in: item)
            },
        ])
        let structures = try XCTUnwrap(DICOMRTStructureSet(dataSet: builder.dataSet))
        XCTAssertEqual(structures.label, "Plan")
        let roi = try XCTUnwrap(structures.rois.first)
        XCTAssertEqual(roi.name, "PTV")
        XCTAssertEqual(roi.interpretedType, "PTV")
        XCTAssertEqual(roi.color.map { [$0.red, $0.green, $0.blue] }, [255, 0, 128])
        XCTAssertEqual(roi.contours.first?.geometricType, "CLOSED_PLANAR")
        XCTAssertEqual(roi.contours.first?.points.map { [$0.x, $0.y, $0.z] }, [[0, 0, 5], [10, 0, 5], [0, 10, 5]])
        XCTAssertNil(DICOMRTDose(dataSet: builder.dataSet))
    }

    func testDoseAndDVH() throws {
        let builder = Builder()
        builder.element("SOPClassUID", "1.2.840.10008.5.1.4.1.1.481.2")
        builder.element("DoseUnits", "GY")
        builder.element("DoseType", "PHYSICAL")
        builder.element("DoseSummationType", "PLAN")
        builder.element("DoseGridScaling", "0.001")
        builder.element("SamplesPerPixel", Data([1, 0]), vr: .US)
        builder.element("PhotometricInterpretation", "MONOCHROME2")
        builder.element("Rows", Data([1, 0]), vr: .US)
        builder.element("Columns", Data([2, 0]), vr: .US)
        builder.element("NumberOfFrames", "2")
        builder.element("BitsAllocated", Data([32, 0]), vr: .US)
        builder.element("BitsStored", Data([32, 0]), vr: .US)
        builder.element("HighBit", Data([31, 0]), vr: .US)
        builder.element("PixelRepresentation", Data([0, 0]), vr: .US)
        builder.element("GridFrameOffsetVector", "0\\2.5")
        let values: [UInt32] = [1000, 2000, 3000, 40000]
        builder.element("PixelData", values.withUnsafeBufferPointer { Data(buffer: $0) }, vr: .OW)
        builder.sequence("DVHSequence", items: [
            { item in
                builder.sequence("DVHReferencedROISequence", in: item, items: [
                    { reference in builder.element("ReferencedROINumber", "1", in: reference) },
                ])
                builder.element("DVHType", "CUMULATIVE", in: item)
                builder.element("DoseUnits", "GY", in: item)
                builder.element("DVHVolumeUnits", "CM3", in: item)
                builder.element("DVHDoseScaling", "0.5", in: item)
                builder.element("DVHNumberOfBins", "2", in: item)
                builder.element("DVHData", "2\\100\\2\\40", in: item)
            },
        ])
        let dose = try XCTUnwrap(DICOMRTDose(dataSet: builder.dataSet))
        XCTAssertEqual(dose.units, "GY")
        XCTAssertEqual([dose.rows, dose.columns, dose.frames], [1, 2, 2])
        XCTAssertEqual(dose.frameOffsets, [0, 2.5])
        XCTAssertEqual(try dose.dose(frame: 0), [1, 2])
        XCTAssertEqual(try dose.dose(frame: 1), [3, 40])
        XCTAssertEqual(try dose.maximumDose(), 40)
        let dvh = try XCTUnwrap(dose.dvhs.first)
        XCTAssertEqual(dvh.roiNumbers, [1])
        XCTAssertEqual(dvh.bins.map { [$0.width, $0.volume] }, [[1, 100], [1, 40]])
    }

    func testPlan() throws {
        let builder = Builder()
        builder.element("SOPClassUID", "1.2.840.10008.5.1.4.1.1.481.5")
        builder.element("RTPlanLabel", "Prostate")
        builder.element("RTPlanGeometry", "PATIENT")
        builder.sequence("DoseReferenceSequence", items: [
            { item in
                builder.element("DoseReferenceNumber", "1", in: item)
                builder.element("TargetPrescriptionDose", "78", in: item)
            },
        ])
        builder.sequence("FractionGroupSequence", items: [
            { item in
                builder.element("FractionGroupNumber", "1", in: item)
                builder.element("NumberOfFractionsPlanned", "39", in: item)
                builder.sequence("ReferencedBeamSequence", in: item, items: [
                    { beam in
                        builder.element("ReferencedBeamNumber", "1", in: beam)
                        builder.element("BeamMeterset", "212.5", in: beam)
                    },
                ])
            },
        ])
        builder.sequence("BeamSequence", items: [
            { beam in
                builder.element("BeamNumber", "1", in: beam)
                builder.element("BeamName", "AP", in: beam)
                builder.element("RadiationType", "PHOTON", in: beam)
                builder.sequence("ControlPointSequence", in: beam, items: [
                    { point in
                        builder.element("ControlPointIndex", "0", in: point)
                        builder.element("GantryAngle", "180", in: point)
                        builder.element("NominalBeamEnergy", "6", in: point)
                        builder.element("IsocenterPosition", "0\\-10\\5", in: point)
                    },
                    { point in
                        builder.element("ControlPointIndex", "1", in: point)
                        builder.element("CumulativeMetersetWeight", "1", in: point)
                    },
                ])
            },
        ])
        let plan = try XCTUnwrap(DICOMRTPlan(dataSet: builder.dataSet))
        XCTAssertEqual(plan.label, "Prostate")
        XCTAssertEqual(plan.prescriptionDose, 78)
        XCTAssertEqual(plan.fractionGroups.first?.fractionsPlanned, 39)
        let beam = try XCTUnwrap(plan.beams.first)
        XCTAssertEqual(beam.meterset, 212.5)
        // The second control point keeps the values it does not change.
        XCTAssertEqual(beam.controlPoints.map(\.gantryAngle), [180, 180])
        XCTAssertEqual(beam.controlPoints.last?.isocenter, [0, -10, 5])
        XCTAssertEqual(beam.controlPoints.last?.cumulativeMetersetWeight, 1)
    }

    /// ROI volumes equal to those of dicompyler-core 0.5.6
    /// (`DicomParser.CalculateStructureVolume`, pydicom 2.4, shapely) on the
    /// synthetic corpus and the pydicom RT Structure Set. dicompyler-core
    /// floors the half area of the end planes: the gap stays below 0.01 cm³.
    /// It also sorts the planes by their position as text, so that its end
    /// planes of External are -10.0 and 7.5 (5868.2876 cm³): the reference
    /// below is its result with the positions as numbers.
    func testROIVolumesMatchDicompylerCore() throws {
        func rois(_ path: String) throws -> [String: DICOMRTStructureSet.ROI] {
            let url = Bundle.module.url(forResource: path, withExtension: nil)
                ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(path)
            let file = try XCTUnwrap(DicomFile(forPath: url.path))
            let set = try XCTUnwrap(DICOMRTStructureSet(dataSet: try XCTUnwrap(file.dataset)))
            return Dictionary(set.rois.map { ($0.name, $0) }) { a, _ in a }
        }
        let synthetic = try rois("Corpus/RT_StructureSet.dcm")
        XCTAssertEqual(try XCTUnwrap(synthetic["EXTERNAL"]?.volume), 54.000247, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(synthetic["PTV"]?.volume), 6.000085, accuracy: 0.01)
        XCTAssertEqual(synthetic["PTV"]?.planes.count, 3)
        let pydicom = try rois("Resources/RT/rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010.dcm")
        XCTAssertEqual(try XCTUnwrap(pydicom["External"]?.volume), 5868.9570, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(pydicom["GTV"]?.volume), 40.4452, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(pydicom["OAR"]?.volume), 26.3642, accuracy: 0.01)
        XCTAssertEqual(pydicom["GTV"]?.planes.count, 12)
        // POINT contours enclose nothing.
        XCTAssertNil(pydicom["Isocentre"]?.volume)
        XCTAssertEqual(pydicom["Isocentre"]?.pointCount, 1)
        let bounds = try XCTUnwrap(pydicom["GTV"]?.bounds)
        XCTAssertLessThan(bounds.minimum.z, bounds.maximum.z)
    }

    /// A square of 10 mm with a hole of 4 mm on three planes 2 mm apart.
    func testAHoleIsSubtractedAndEndPlanesCountForHalf() {
        func square(_ side: Double, z: Double) -> DICOMRTStructureSet.Contour {
            let h = side / 2
            return DICOMRTStructureSet.Contour(geometricType: "CLOSED_PLANAR",
                                               points: [(-h, -h, z), (h, -h, z), (h, h, z), (-h, h, z)], referencedSOPInstanceUIDs: [])
        }
        XCTAssertEqual(square(10, z: 0).area, 100)
        let contours = [0.0, 2, 4].flatMap { [square(4, z: $0), square(10, z: $0)] }
        let roi = DICOMRTStructureSet.ROI(number: 1, name: "RING", description: nil, frameOfReferenceUID: nil,
                                          generationAlgorithm: nil, color: nil, interpretedType: nil, contours: contours)
        // (0.5 + 1 + 0.5) × (100 − 16) mm² × 2 mm = 336 mm³.
        XCTAssertEqual(try XCTUnwrap(roi.volume), 0.336, accuracy: 1e-9)
        XCTAssertEqual(roi.planes, [0, 2, 4])
    }
}
