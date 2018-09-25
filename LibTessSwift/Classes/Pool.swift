//
//  Pool.swift
//  Pods
//
//  Created by Luiz Fernando Silva on 28/02/17.
//
//

/// Handy pooler
internal class Pool<Element> where Element: EmptyInitializable {
    
    /// Inner pool of objects
    private var pool: Array<UnsafeMutablePointer<Element>> = []
    private var freeIndices: Set<Int> = []
    private var indices: [UnsafeMutablePointer<Element>: Int] = [:]
    
    /// Resets the contents of this pool
    func reset() {
        free()
    }
    
    func free() {
        for pointer in pool {
            pointer.deallocate()
        }
        
        pool.removeAll()
        freeIndices.removeAll()
        indices.removeAll()
    }
    
    /// Pulls a new instance from this pool, creating it if necessary.
    func pull() -> UnsafeMutablePointer<Element> {
        if let free = freeIndices.popFirst() {
            pool[free].initialize(to: Element())
            
            return pool[free]
        }
        
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: 1)
        pointer.initialize(to: Element())
        indices[pointer] = pool.count
        pool.append(pointer)
        
        return pointer
    }
    
    /// Calls a given closure with a temporary value from this pool.
    /// Re-pooling the object on this pool during the call of this method is a
    /// programming error and should not be done.
    func withTemporary<U>(execute closure: (UnsafeMutablePointer<Element>) throws -> (U)) rethrows -> U {
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: 1)
        pointer.initialize(to: Element())
        defer {
            pointer.deinitialize()
            pointer.deallocate()
        }

        return try closure(pointer)
    }
    
    /// Repools a value for later retrieval with .pull()
    func repool(_ v: UnsafeMutablePointer<Element>) {
        if let index = indices[v] {
            freeIndices.insert(index)
        } else {
            assertionFailure("Tried repooling pointer that was not pulled from this pool")
        }
        
        v.deinitialize()
    }
}
