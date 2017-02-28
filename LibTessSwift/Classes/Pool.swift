//
//  Pool.swift
//  Pods
//
//  Created by Luiz Fernando Silva on 28/02/17.
//
//

/// Handy pooler
internal class Pool<T> where T: AnyObject & EmptyInitializable {
    
    /// Inner pool of objects
    fileprivate(set) internal var pool: ContiguousArray<T> = []
    
    /// Collects all objects initialized by this pool
    fileprivate(set) internal var totalCreated: ContiguousArray<T> = []
    
    /// Resets the contents of this pool
    func reset() {
        pool.removeAll()
        totalCreated.removeAll()
    }
    
    /// Pulls a new instance from this pool, creating it if necessary.
    func pull() -> T {
        if(pool.count == 0) {
            let v = T()
            
            totalCreated.append(v)
            
            return v
        }
        
        return pool.removeFirst()
    }
    
    /// Repools a value for later retrieval with .pull()
    func repool(_ v: T) {
        pool.append(v)
    }
}
