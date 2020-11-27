//
//  WeakArray.swift
//  HTMLArchiving
//
//  Created by Ben Gottlieb on 11/18/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

import Foundation

public struct WeakRef<Element: AnyObject> {
    public weak var object: Element?
}

extension WeakRef: Hashable {
    public static func ==(lhs: WeakRef, rhs: WeakRef) -> Bool {
        if let leftObj = lhs.object, let rightObj = rhs.object { return leftObj === rightObj }
        return lhs.object === rhs.object
    }

    public func hash(into hasher: inout Hasher) {
        if let obj = self.object as? AnyHashable { obj.hash(into: &hasher) }
    }
    public var hashValue: Int {
        if let obj = self.object as? AnyHashable { return obj.hashValue }
        return 0
    }
}

public struct WeakArrayGenerator<Element: AnyObject>: IteratorProtocol {
    let array: [Element]
    var index = 0
    
    public mutating func next() -> Element? {
        if index >= self.array.count { return nil }
        let value: Element? = self.array[index]
        index += 1
        return value
    }
    
    init(_ a: WeakArray<Element>) {
        array = a.array.compactMap { $0.object }
    }
}

public struct WeakArray<Element: AnyObject>: Sequence, ExpressibleByArrayLiteral {
    public func makeIterator() -> WeakArrayGenerator<Element> { return WeakArrayGenerator<Element>(self) }
    public var array: Array<WeakRef<Element>> = []
    
    public var count: Int { return self.array.count }
    public mutating func append(_ object: Element) { self.array.append(WeakRef(object: object)) }
    
    public init(_ starter: [Element] = []) {
        self.array = starter.map { WeakRef(object: $0) }
    }
    
    public init(arrayLiteral: Element...) {
        for element in arrayLiteral {
            self.array.append(WeakRef(object: element))
        }
    }
    
    public subscript(index: Int) -> Element? {
        get {
            return self.array[index].object
        }
        set {
            if let obj = newValue { self.array[index] = WeakRef(object: obj) }
        }
    }

    public mutating func remove(at index: Int) { self.array.remove(at: index) }
    public var first: Element? { return self.array.first?.object }
    public var last: Element? { return self.array.last?.object }
}

