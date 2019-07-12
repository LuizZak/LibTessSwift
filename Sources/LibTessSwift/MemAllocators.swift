//
//  MemPool.swift
//  Pods
//
//  Created by Luiz Fernando Silva on 15/04/17.
//
//

#if os(macOS) || os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin.C
#elseif os(Linux)
import Glibc
#else
#error("Unsupported platform")
#endif

func stdAlloc(userData: UnsafeMutableRawPointer?, size: Int) -> UnsafeMutableRawPointer {
    let allocated = userData?.assumingMemoryBound(to: Int.self)
    allocated?.pointee += size
    
    return malloc(size)
}

func stdFree(userData: UnsafeMutableRawPointer?, ptr: UnsafeMutableRawPointer) {
    free(ptr)
}

struct MemPool {
    var buf: UnsafeMutablePointer<UInt8>
    var cap: Int
    var size: Int
}

func poolAlloc(userData: UnsafeMutableRawPointer?, size: Int) -> UnsafeMutableRawPointer? {
    guard let userData = userData else {
        print("Missing pool allocator's MemPool parameter")
        return nil
    }
    
    let pool = userData.assumingMemoryBound(to: MemPool.self)
    
    let size = (size+0x7) & ~0x7;
    
    if (pool.pointee.size + size < pool.pointee.cap)
    {
        let ptr = pool.pointee.buf + pool.pointee.size;
        pool.pointee.size += size
        
        return UnsafeMutableRawPointer(ptr)
    }
    
    print("out of mem: \(pool.pointee.size + size) < \(pool.pointee.cap)!\n")
    
    return nil
}

func poolFree(userData: UnsafeMutableRawPointer?, ptr: UnsafeMutableRawPointer) {
    // Not used
}
