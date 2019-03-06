//
//  PriorityHeap.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

internal struct PQHandle {
    static let Invalid: Int = 0x0fffffff
    
    internal var _handle: Int
    
    init() {
        _handle = 0
    }
    
    init(handle: Int) {
        _handle = handle
    }
}

internal class PriorityHeap<TValue> {
    typealias LessOrEqual = (_ lhs: TValue, _ rhs: TValue) -> Bool
    
    private var _leq: LessOrEqual
    private var _nodes: [Int]
    private var _handles: Array<HandleElem?>
    private var _size: Int = 0, _max: Int = 0
    private var _freeList = 0
    private var _initialized = false
    
    var Empty: Bool { get { return _size == 0 } }
    
    init(_ initialSize: Int, _ leq: @escaping LessOrEqual) {
        _leq = leq
        
        _nodes = Array(repeating: 0, count: initialSize + 1)
        _handles = Array(repeating: nil, count: initialSize + 1)

        _size = 0
        _max = initialSize
        _freeList = 0
        _initialized = false

        _nodes[1] = 1
        _handles[1] = HandleElem(key: nil)
    }
    
    private func floatDown(_ curr: Int) {
        var curr = curr
        var child = 0
        var hCurr = 0, hChild = 0
        
        hCurr = _nodes[curr]
        while true {
            child = curr << 1
            
            if child < _size && _leq(handleElemKey(fromNode: child + 1)!, handleElemKey(fromNode: child)!) {
                child += 1
            }
            
            assert(child <= _max)
            
            hChild = _nodes[child]
            if child > _size || _leq(_handles[hCurr]!._key!, _handles[hChild]!._key!) {
                _nodes[curr] = hCurr
                _handles[hCurr]!._node = curr
                break
            }
            
            _nodes[curr] = hChild
            _handles[hChild]!._node = curr
            curr = child
        }
    }
    
    private func floatUp(_ curr: Int) {
        var curr = curr
        var parent = 0
        var hCurr = 0, hParent = 0
        
        hCurr = _nodes[curr]
        while true {
            parent = curr >> 1
            hParent = _nodes[parent]
            
            if parent == 0 || _leq(_handles[hParent]!._key!, _handles[hCurr]!._key!) {
                _nodes[curr] = hCurr
                _handles[hCurr]!._node = curr
                break
            }
            _nodes[curr] = hParent
            _handles[hParent]!._node = curr
            curr = parent
        }
    }
    
    func initialize() {
        var i = _size
        while i >= 1 {
            defer { i -= 1 }
            floatDown(i)
        }
        _initialized = true
    }
    
    func insert(_ value: TValue) -> PQHandle {
        let curr = _size + 1
        _size += 1
        if (curr * 2) > _max {
            _max <<= 1
            
            let diffN = _nodes.count - _max + 1
            let diffH = _handles.count - _max + 1
            
            let subN: [Int] = Array(repeating: 0, count: diffN)
            let subH = ContiguousArray<HandleElem?>(repeating: nil, count: diffH)
            
            _nodes.append(contentsOf: subN)
            _handles.append(contentsOf: subH)
        }
        
        var free = 0
        if _freeList == 0 {
            free = curr
        } else {
            free = _freeList
            _freeList = _handles[free]!._node
        }
        
        _nodes[curr] = free
        if _handles[free] == nil {
            _handles[free] = HandleElem(key: value, node: curr)
        } else {
            withHandleEmen(atIndex: free) { handle in
                handle!._node = curr
                handle!._key = value
            }
        }
        
        if _initialized {
            floatUp(curr)
        }
        
        assert(free != PQHandle.Invalid)
        return PQHandle(handle: free)
    }

    func extractMin() -> TValue? {
        assert(_initialized)
        
        let hMin = _nodes[1]
        let min = _handles[hMin]!._key
        
        if _size > 0 {
            _nodes[1] = _nodes[_size]
            
            withHandleEmen(fromNode: 1) { handle in
                handle!._node = 1
            }
            
            withHandleEmen(atIndex: hMin) { handle in
                handle!._key = nil
                handle!._node = _freeList
            }
            
            _freeList = hMin
            
            _size -= 1
            if _size > 0 {
                floatDown(1)
            }
        }

        return min
    }

    func minimum() -> TValue? {
        assert(_initialized)
        return _handles[_nodes[1]]!._key
    }

    func remove(_ handle: PQHandle) {
        assert(_initialized)
        
        let hCurr = handle._handle
        assert(hCurr >= 1 && hCurr <= _max && handleElemKey(atIndex: hCurr) != nil)
        
        let curr = handleElem(atIndex: hCurr)!._node
        _nodes[curr] = _nodes[_size]
        
        withHandleEmen(fromNode: curr) { handle in
            handle!._node = curr
        }
        
        _size -= 1
        if curr <= _size {
            let k1 = handleElemKey(fromNode: curr >> 1)!
            let k2 = handleElemKey(fromNode: curr)!
            
            if curr <= 1 || _leq(k1, k2) {
                floatDown(curr)
            } else {
                floatUp(curr)
            }
        }
        
        withHandleEmen(atIndex: hCurr) { handle in
            handle!._key = nil
            handle!._node = _freeList
        }
        
        _freeList = hCurr
    }
    
    private func handleElem(atIndex index: Int) -> HandleElem? {
        return _handles[index]
    }
    
    private func handleElemKey(atIndex index: Int) -> TValue? {
        return handleElem(atIndex: index)?._key
    }
    
    private func withHandleEmen(atIndex index: Int, do closure: (inout HandleElem?) -> Void) {
        closure(&_handles[index])
    }
    
    private func withHandleEmen(fromNode index: Int, do closure: (inout HandleElem?) -> Void) {
        closure(&_handles[_nodes[index]])
    }
    
    private func handleElem(fromNode index: Int) -> HandleElem? {
        return handleElem(atIndex: _nodes[index])
    }
    
    private func handleElemKey(fromNode index: Int) -> TValue? {
        return handleElem(fromNode: index)?._key
    }
}

fileprivate extension PriorityHeap {
    struct HandleElem {
        var _key: TValue?
        var _node: Int
        
        init(key: TValue?) {
            _key = key
            _node = 0
        }
        
        init(key: TValue?, node: Int) {
            _key = key
            _node = node
        }
    }
}
