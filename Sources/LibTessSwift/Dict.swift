//
//  Dict.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

typealias Node<T> = UnsafeMutablePointer<_Node<T>>

internal struct _Node<TValue>: Linked {
    var key: TValue?
    var prev: Node<TValue>?
    var next: Node<TValue>?
    
    var _next: Node<TValue>? {
        return next
    }
    
    init() {
        
    }
    
    init(Key: TValue) {
        self.key = Key
    }
}

internal final class Dict<TValue> {
    typealias LessOrEqual = (_ lhs: TValue, _ rhs: TValue) -> Bool
    
    private var _leq: LessOrEqual
    var _head: Node<TValue>
    
    init(leq: @escaping LessOrEqual) {
        _leq = leq
        
        _head = UnsafeMutablePointer.allocate(capacity: 1)
        _head.initialize(to: _Node<TValue>())
        _head.pointee.prev = _head
        _head.pointee.next = _head
    }
    
    deinit {
        _head.loop { node in
            if node.pointee.prev != _head {
                node.pointee.prev?.deinitialize(count: 1).deallocate()
            }
            node.pointee.next = nil
        }
        _head.deinitialize(count: 1).deallocate()
    }
    
    func insert(key: TValue) -> Node<TValue> {
        return insertBefore(node: _head, key: key)
    }
    
    func insertBefore(node: Node<TValue>, key: TValue) -> Node<TValue> {
        var node = node
        
        repeat {
            node = node.pointee.prev!
        } while node.pointee.key != nil && !_leq(node.pointee.key!, key)
        
        let newNode = UnsafeMutablePointer<_Node<TValue>>.allocate(capacity: 1)
        newNode.initialize(to: _Node<TValue>())
        newNode.pointee.key = key
        newNode.pointee.next = node.pointee.next
        node.pointee.next?.pointee.prev = newNode
        newNode.pointee.prev = node
        node.pointee.next = newNode
        
        return newNode
    }
    
    func find(key: TValue) -> Node<TValue> {
        var node = _head
        repeat {
            node = node.pointee.next!
        } while node.pointee.key != nil && !_leq(key, node.pointee.key!)
        return node
    }
    
    func min() -> Node<TValue>? {
        return _head.pointee.next
    }
    
    func remove(node: Node<TValue>) {
        node.pointee.next?.pointee.prev = node.pointee.prev
        node.pointee.prev?.pointee.next = node.pointee.next
        node.deinitialize(count: 1).deallocate()
    }
}
