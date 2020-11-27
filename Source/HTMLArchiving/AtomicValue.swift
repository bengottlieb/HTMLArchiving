//
//  AtomicValue.swift
//  HTMLArchiving
//
//  Created by Ben Gottlieb on 11/18/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

import Foundation

public class AtomicValue<T> {
    private let lock = DispatchSemaphore(value: 1)
    private var cache: T
    
    public init(_ value: T) {
        self.cache = value
    }
    
    public var value: T {
        get {
            self.lock.wait()
            defer { self.lock.signal() }
            return self.cache
        }
        set {
            self.lock.wait()
            defer { self.lock.signal() }
            self.cache = newValue
        }
    }
    
    
}
