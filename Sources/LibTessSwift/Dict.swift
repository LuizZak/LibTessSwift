//
//  Dict.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

typealias _Node<T> = UnsafeMutablePointer<Node<T>>

internal struct Node<TValue>: Linked {
    var Key: TValue?
    var Prev: UnsafeMutablePointer<Node>?
    var Next: UnsafeMutablePointer<Node>?
    
    var _next: UnsafeMutablePointer<Node>! {
        return Next
    }
    
    init() {
        
    }
    
    init(Key: TValue) {
        self.Key = Key
    }
}

internal final class Dict<TValue> {
    typealias LessOrEqual = (_ lhs: TValue, _ rhs: TValue) -> Bool
    
    private var _leq: LessOrEqual
    var _head: _Node<TValue>
    
    public init(leq: @escaping LessOrEqual) {
        _leq = leq
        
        _head = UnsafeMutablePointer.allocate(capacity: 1)
        _head.initialize(to: Node<TValue>())
        _head.pointee.Prev = _head
        _head.pointee.Next = _head
    }
    
    deinit {
        // Dismount references to allow ARC to do its job
        _head.loop { node in
            if node.pointee.Prev != _head {
                node.pointee.Prev?.deinitialize(count: 1)
                node.pointee.Prev?.deallocate()
            }
            node.pointee.Next = nil
        }
        _head.deinitialize(count: 1)
        _head.deallocate()
    }
    
    public func Insert(key: TValue) -> _Node<TValue> {
        return InsertBefore(node: _head, key: key)
    }
    
    public func InsertBefore(node: _Node<TValue>, key: TValue) -> _Node<TValue> {
        var node = node
        
        repeat {
            node = node.pointee.Prev!
        } while (node.pointee.Key != nil && !_leq(node.pointee.Key!, key))
        
        let newNode = UnsafeMutablePointer<Node<TValue>>.allocate(capacity: 1)
        newNode.initialize(to: Node<TValue>())
        newNode.pointee.Key = key
        newNode.pointee.Next = node.pointee.Next
        node.pointee.Next?.pointee.Prev = newNode
        newNode.pointee.Prev = node
        node.pointee.Next = newNode
        
        return newNode
    }
    
    public func Find(key: TValue) -> _Node<TValue> {
        var node = _head
        repeat {
            node = node.pointee.Next!
        } while (node.pointee.Key != nil && !_leq(key, node.pointee.Key!))
        return node
    }
    
    public func Min() -> _Node<TValue>? {
        return _head.pointee.Next
    }
    
    public func Remove(node: _Node<TValue>) {
        node.pointee.Next?.pointee.Prev = node.pointee.Prev
        node.pointee.Prev?.pointee.Next = node.pointee.Next
        
        node.deallocate()
    }
}
