//
//  UITableViewCellTests.swift
//  Rex
//
//  Created by David Rodrigues on 19/04/16.
//  Copyright © 2016 Neil Pankey. All rights reserved.
//

import XCTest
import ReactiveSwift
import ReactiveCocoa
class UITableViewCellTests: XCTestCase {
    
    func testPrepareForReuse() {

        let titleProperty = MutableProperty("John")

        let cell = UITableViewCell()

        guard let label = cell.textLabel else {
            fatalError()
        }

        label.reactive.text <~
            titleProperty
                .producer
                .take(until: cell.reactive.prepareForReuse)

        XCTAssertEqual(label.text, "John")

        titleProperty <~ SignalProducer(value: "Frank")
        XCTAssertEqual(label.text, "Frank")

        cell.prepareForReuse()

        titleProperty <~ SignalProducer(value: "Will")
        XCTAssertEqual(label.text, "Frank")
    }
}
