//
//  Dict.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

typealias Node<T> = UnsafeMutablePointer<_Node<T>>

internal struct _Node<TValue>: Linked {
    var Key: TValue?
    var Prev: Node<TValue>?
    var Next: Node<TValue>?
    
    var _next: Node<TValue>? {
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
    var _head: Node<TValue>
    
    public init(leq: @escaping LessOrEqual) {
        _leq = leq
        
        _head = UnsafeMutablePointer.allocate(capacity: 1)
        _head.initialize(to: _Node<TValue>())
        _head.pointee.Prev = _head
        _head.pointee.Next = _head
    }
    
    deinit {
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
    
    public func Insert(key: TValue) -> Node<TValue> {
        return InsertBefore(node: _head, key: key)
    }
    
    public func InsertBefore(node: Node<TValue>, key: TValue) -> Node<TValue> {
        var node = node
        
        repeat {
            node = node.pointee.Prev!
        } while (node.pointee.Key != nil && !_leq(node.pointee.Key!, key))
        
        let newNode = UnsafeMutablePointer<_Node<TValue>>.allocate(capacity: 1)
        newNode.initialize(to: _Node<TValue>())
        newNode.pointee.Key = key
        newNode.pointee.Next = node.pointee.Next
        node.pointee.Next?.pointee.Prev = newNode
        newNode.pointee.Prev = node
        node.pointee.Next = newNode
        
        return newNode
    }
    
    public func Find(key: TValue) -> Node<TValue> {
        var node = _head
        repeat {
            node = node.pointee.Next!
        } while (node.pointee.Key != nil && !_leq(key, node.pointee.Key!))
        return node
    }
    
    public func Min() -> Node<TValue>? {
        return _head.pointee.Next
    }
    
    public func Remove(node: Node<TValue>) {
        node.pointee.Next?.pointee.Prev = node.pointee.Prev
        node.pointee.Prev?.pointee.Next = node.pointee.Next
        node.deinitialize(count: 1)
        node.deallocate()
    }
}
