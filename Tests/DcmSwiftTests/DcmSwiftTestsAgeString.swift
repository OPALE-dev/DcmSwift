//
//  DcmSwiftTestsAgeString.swift
//
//
//  Created by Colombe on 09/07/2021.
//

import XCTest
import DcmSwift

/**
 */
class DcmSwiftTestsAgeString: XCTestCase {
    
    //MARK: -
    public func testAgeStringPositiveAge() {
        let currentDate = Date()
        var dateComponent = DateComponents()
        
        // two years in the past
        dateComponent.year = -2
                
        if let futureDate = Calendar.current.date(byAdding: dateComponent, to: currentDate) {
            // should not be nil
            XCTAssertNotNil(AgeString(birthdate: futureDate))
        }
    }
    
    public func testAgeStringNegativeAge() {
        let currentDate = Date()
        var dateComponent = DateComponents()
        
        // two years in the future
        dateComponent.year = 2
                
        if let futureDate = Calendar.current.date(byAdding: dateComponent, to: currentDate) {
            // should be nil
            XCTAssertNil(AgeString(birthdate: futureDate))
        }
    }

    // Tests Colombe
    
    func testAgeStringInitWithString() {
        let works = "005D"
        if let res = AgeString.init(ageString: works) {
            XCTAssertNotNil(res)
        }
        
        let dsntWorks = "marche pas"
        if let res = AgeString.init(ageString: dsntWorks) {
            XCTAssertNil(res)
        }
    }

    
    func testAgeStringValidate() {
        let works = "005D"
        if let astrWorks = AgeString.init(ageString: works) {
            XCTAssertTrue(astrWorks.validate(age: works))
        }
        
        let dsntWorks = "hello"
        if let astrDsntWorks = AgeString.init(ageString: dsntWorks) {
            XCTAssertFalse(astrDsntWorks.validate(age: dsntWorks))
        }
    }
    
    func testAgeStringAge() {
        let works = "005D"
        let astrWorks = AgeString.init(ageString: works)
        XCTAssertNotNil(astrWorks?.age(withPrecision: .days))
        
        let dsntWorks = "hello"
        let astrDsntWorks = AgeString.init(ageString: dsntWorks)
        XCTAssertNil(astrDsntWorks?.age(withPrecision: .days))
    }
    
    func testAgeStringVariations() {
        let ages = ["012A", "220M", "034W", "005D"]
        for age in ages  {
            if let astrWorks = AgeString.init(ageString: age) {
                XCTAssertTrue(astrWorks.validate(age: age))
            }
        }
    }
    
    func testAgeStringFormat() {
        let source  = ["334D", "034Y", "111W", "002D"]
        let dest    = ["10 months", "34 years", "2 years", "2 days"]
        
        var index = 0
        
        for s in source {
            let agStr = AgeString.init(ageString: s)
            
            if let a = agStr  {
                XCTAssertEqual(a.format(), dest[index])
            }
            
            index += 1
        }
    }
    
}


