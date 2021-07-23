//
//  File.swift
//  
//
//  Created by Rafael Warnault on 23/07/2021.
//

import Foundation


internal extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}
