//
//  DcmRT.swift
//
//  Prints RT Structure Sets, Doses, and Plans.
//

import ArgumentParser
import DcmSwift
import Foundation

@main
struct DcmRT: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the ROIs of an RT Structure Set, the dose grid of an RT Dose, or the beams of an RT Plan.")

    @Argument(help: "DICOM file")
    var path: String

    @Flag(help: "Print JSON, with the contour points, dose values, and control points")
    var json = false

    mutating func run() throws {
        guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
            throw ValidationError("cannot read \(path) as DICOM")
        }
        if let structures = DICOMRTStructureSet(dataSet: dataSet) {
            if json {
                try output(["structureSet": [
                    "label": structures.label,
                    "rois": structures.rois.map { roi -> [String: Any] in
                        [
                            "number": roi.number, "name": roi.name, "type": nullable(roi.interpretedType),
                            "color": nullable(roi.color.map { [$0.red, $0.green, $0.blue] }),
                            "contours": roi.contours.map { contour in
                                ["type": contour.geometricType, "points": contour.points.map { [$0.x, $0.y, $0.z] }]
                            },
                        ]
                    },
                ]])
                return
            }
            print("RT Structure Set \(structures.label): \(structures.rois.count) ROIs")
            for roi in structures.rois {
                print("  \(roi.number). \(roi.name) \(roi.interpretedType ?? ""): \(roi.contours.count) contours")
            }
        } else if let dose = DICOMRTDose(dataSet: dataSet) {
            if json {
                try output(["dose": [
                    "units": dose.units, "type": dose.type, "summationType": dose.summationType, "rows": dose.rows,
                    "columns": dose.columns, "frames": dose.frames, "gridScaling": dose.gridScaling,
                    "position": dose.imagePosition, "pixelSpacing": dose.pixelSpacing, "frameOffsets": dose.frameOffsets,
                    "values": try (0..<dose.frames).map { try dose.dose(frame: $0) },
                    "dvhs": dose.dvhs.map { dvh in
                        ["rois": dvh.roiNumbers, "type": dvh.type, "doseUnits": dvh.doseUnits,
                         "volumeUnits": dvh.volumeUnits, "bins": dvh.bins.map { [$0.width, $0.volume] }]
                    },
                ]])
                return
            }
            print("RT Dose: \(dose.columns) x \(dose.rows) x \(dose.frames), \(dose.units) \(dose.type) \(dose.summationType), "
                  + "maximum \(try dose.maximumDose())")
            for dvh in dose.dvhs {
                print("  DVH of ROI \(dvh.roiNumbers.map(String.init).joined(separator: ", ")): \(dvh.type), \(dvh.bins.count) bins")
            }
        } else if let plan = DICOMRTPlan(dataSet: dataSet) {
            if json {
                try output(["plan": [
                    "label": plan.label, "date": nullable(plan.date), "prescriptionDose": nullable(plan.prescriptionDose),
                    "fractionGroups": plan.fractionGroups.map { ["fractions": nullable($0.fractionsPlanned), "beams": $0.beamNumbers] },
                    "beams": plan.beams.map { beam -> [String: Any] in
                        ["number": beam.number, "name": nullable(beam.name), "radiationType": nullable(beam.radiationType),
                         "meterset": nullable(beam.meterset),
                         "controlPoints": beam.controlPoints.map { ["gantry": nullable($0.gantryAngle),
                                                                    "energy": nullable($0.nominalEnergy)] }]
                    },
                ]])
                return
            }
            print("RT Plan \(plan.label): prescription \(plan.prescriptionDose.map { "\($0) Gy" } ?? "-")")
            for beam in plan.beams {
                print("  Beam \(beam.number) \(beam.name ?? ""): \(beam.radiationType ?? "") \(beam.controlPoints.count) control points, meterset \(beam.meterset.map { String($0) } ?? "-")")
            }
        } else {
            throw ValidationError("\(path) is not an RT Structure Set, Dose, or Plan")
        }
    }

    private func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private func output(_ object: Any) throws {
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: object))
    }
}
