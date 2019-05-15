//
//  DateExtensions.swift
//  DicomiX
//
//  Created by paul on 14/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import DcmSwift

extension Date {
    public func format(accordingTo: DicomConstants.VR) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short

        if accordingTo == .DA {
            df.timeStyle = .none
        }
        else if accordingTo == .TM {
            df.dateStyle = .none
        }

        return df.string(from: self)
    }// format
}
