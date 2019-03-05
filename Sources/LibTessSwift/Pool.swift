//
//  Pool.swift
//  Pods
//
//  Created by Luiz Fernando Silva on 28/02/17.
//
//

/// Handy pooler
internal class Pool<Element> where Element: EmptyInitializable {
    private let emptyElement = Element()
    
    /// Inner pool of objects
    private var pool: Array<UnsafeMutablePointer<Element>> = []
    private var freeIndices: Set<Int> = []
    private var indices: [UnsafeMutablePointer<Element>: Int] = [:]
    
    deinit {
        free()
    }
    
    func free() {
        for (i, pointer) in pool.enumerated() {
            if !freeIndices.contains(i) {
                pointer.deinitialize(count: 1)
            }
            pointer.deallocate()
        }
        
        pool.removeAll()
        freeIndices.removeAll()
        indices.removeAll()
    }
    
    /// Pulls a new instance from this pool, creating it, if necessary.
    func pull() -> UnsafeMutablePointer<Element> {
        if let free = freeIndices.popFirst() {
            pool[free].initialize(to: emptyElement)
            
            return pool[free]
        }
        
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: 1)
        pointer.initialize(to: emptyElement)
        indices[pointer] = pool.count
        pool.append(pointer)
        
        return pointer
    }
    
    /// Calls a given closure with a temporary value from this pool.
    /// Re-pooling the object on this pool during the call of this method is a
    /// programming error and should not be done.
    func withTemporary<U>(execute closure: (UnsafeMutablePointer<Element>) throws -> (U)) rethrows -> U {
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: 1)
        pointer.initialize(to: emptyElement)
        defer {
            pointer.deinitialize(count: 1).deallocate()
        }

        return try closure(pointer)
    }
    
    /// Repools a value for later retrieval with `.pull()`
    ///
    /// - precondition: `v` was a pointer pulled from this Pool with `Pool.pull()`
    func repool(_ v: UnsafeMutablePointer<Element>) {
        if let index = indices[v] {
            freeIndices.insert(index)
        } else {
            preconditionFailure("Tried repooling pointer that was not pulled from this pool")
        }
        
        v.deinitialize(count: 1)
    }
}
