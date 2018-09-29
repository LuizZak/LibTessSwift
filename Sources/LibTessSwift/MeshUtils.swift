//
//  MeshUtils.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

import simd

/// Objects that can be initialized using a parameterless init
public protocol EmptyInitializable {
    init()
}

#if arch(x86_64) || arch(arm64)
public typealias Real = Double
public typealias Vector3 = double3

public extension Vector3 {
    public static let zero = double3()
    
    public static func longAxis(v: inout Vector3) -> Int {
        var i = 0
        if abs(v.y) > abs(v.x) { i = 1 }
        if abs(v.z) > abs(i == 0 ? v.x : v.y) { i = 2 }
        
        return i
    }
}
#else
public typealias Real = Float
public typealias Vector3 = float3

public extension Vector3 {
    public static let zero = float3()
    
    public static func longAxis(v: inout Vector3) -> Int {
        var i = 0
        if abs(v.y) > abs(v.x) { i = 1 }
        if abs(v.z) > abs(i == 0 ? v.x : v.y) { i = 2 }
        
        return i
    }
}
#endif

/// Describes an object that can be chained with other instances of itself
/// indefinitely. This also supports looped links that point circularly.
internal protocol Linked {
    var _next: UnsafeMutablePointer<Self>! { get }
}

internal class MeshUtils {
    
    public static let Undef: Int = ~0
    
    public final class _Vertex: Linked, EmptyInitializable {
        internal var _prev: Vertex!
        internal var _next: Vertex!
        internal var _anEdge: Edge!

        internal var _coords: Vector3 = .zero
        internal var _s: Real = 0, _t: Real = 0
        internal var _pqHandle: PQHandle = PQHandle()
        internal var _n: Int = 0
        internal var _data: Any?
        
        init() {
            
        }
    }

    public struct _Face: Linked, EmptyInitializable {
        internal var _prev: Face!
        internal var _next: Face!
        internal var _anEdge: Edge!
        
        internal var _n: Int = 0
        internal var _marked = false, _inside = false

        internal var VertsCount: Int {
            var n = 0
            var eCur = _anEdge
            repeat {
                n += 1
                eCur = eCur?.pointee._Lnext
            } while eCur != _anEdge
            return n
        }
        
        init() {
            
        }
    }

    public struct EdgePair {
        internal var _e: Edge?
        internal var _eSym: Edge?
    }

    public final class _Edge: Linked, EmptyInitializable {
        public static var pool: Array<MeshUtils._Edge> = []
        
        internal var _pair: EdgePair?
        internal var _next: Edge!
        private var __Sym: Edge?
        internal var _Sym: Edge! {
            get {
                return __Sym
            }
            set {
                __Sym = newValue
            }
        }
        internal var _Onext: Edge!
        internal var _Lnext: Edge!
        internal var _Org: Vertex!
        internal var _Lface: Face!
        internal var _activeRegion: ActiveRegion!
        internal var _winding: Int = 0

        internal var _Rface: Face! { get { return _Sym.pointee._Lface } set { _Sym.pointee._Lface = newValue } }
        internal var _Dst: Vertex! { get { return _Sym.pointee._Org }  set { _Sym.pointee._Org = newValue } }

        internal var _Oprev: Edge! { get { return _Sym.pointee._Lnext } set { _Sym.pointee._Lnext = newValue } }
        internal var _Lprev: Edge! { get { return _Onext.pointee._Sym } set { _Onext.pointee._Sym = newValue } }
        internal var _Dprev: Edge! { get { return _Lnext.pointee._Sym } set { _Lnext.pointee._Sym = newValue } }
        internal var _Rprev: Edge! { get { return _Sym.pointee._Onext } set { _Sym.pointee._Onext = newValue } }
        internal var _Dnext: Edge! { get { return _Rprev?.pointee._Sym } set { _Rprev?.pointee._Sym = newValue } }
        internal var _Rnext: Edge! { get { return _Oprev?.pointee._Sym } set { _Oprev?.pointee._Sym = newValue } }
        
        internal static func EnsureFirst(e: inout Edge) {
            if (e == e.pointee._pair?._eSym) {
                e = e.pointee._Sym
            }
        }
        
        public init() {
            
        }
    }
    
    /// <summary>
    /// Splice( a, b ) is best described by the Guibas/Stolfi paper or the
    /// CS348a notes (see Mesh.cs). Basically it modifies the mesh so that
    /// a->Onext and b->Onext are exchanged. This can have various effects
    /// depending on whether a and b belong to different face or vertex rings.
    /// For more explanation see Mesh.Splice().
    /// </summary>
    public static func Splice(_ a: Edge, _ b: Edge) {
        let aOnext = a.pointee._Onext
        let bOnext = b.pointee._Onext
        
        aOnext?.pointee._Sym.pointee._Lnext = b
        bOnext?.pointee._Sym.pointee._Lnext = a
        a._Onext = bOnext
        b._Onext = aOnext
    }
    
    /// <summary>
    /// Return signed area of face.
    /// </summary>
    public static func FaceArea(_ f: Face) -> Real {
        var area: Real = 0
        var e = f._anEdge!
        repeat {
            area += (e._Org._s - e._Dst._s) * (e._Org._t + e._Dst._t)
            e = e._Lnext
        } while (e != f._anEdge)
        return area
    }
}

typealias Face = UnsafeMutablePointer<MeshUtils._Face>
typealias Edge = UnsafeMutablePointer<MeshUtils._Edge>
typealias Vertex = UnsafeMutablePointer<MeshUtils._Vertex>

extension UnsafeMutablePointer where Pointee == MeshUtils._Face {
    var _prev: Face! {
        get { return pointee._prev }
        nonmutating set { pointee._prev = newValue }
    }
    var _next: Face! {
        get { return pointee._next }
        nonmutating set { pointee._next = newValue }
    }
    var _anEdge: Edge! {
        get { return pointee._anEdge }
        nonmutating set { pointee._anEdge = newValue }
    }
    
    var VertsCount: Int {
        return pointee.VertsCount
    }
    
    var _n: Int {
        get { return pointee._n }
        nonmutating set { pointee._n = newValue }
    }
    
    var _marked: Bool {
        get { return pointee._marked }
        nonmutating set { pointee._marked = newValue }
    }
    var _inside: Bool {
        get { return pointee._inside }
        nonmutating set { pointee._inside = newValue }
    }
}

extension UnsafeMutablePointer where Pointee == MeshUtils._Edge {
    internal var _pair: MeshUtils.EdgePair? {
        get { return pointee._pair }
        nonmutating set { return pointee._pair = newValue }
    }
    internal var _next: Edge! {
        get { return pointee._next }
        nonmutating set { pointee._next = newValue }
    }
    internal var _Sym: Edge! {
        get {
            return pointee._Sym
        }
        nonmutating set {
            pointee._Sym = newValue
        }
    }
    internal var _Onext: Edge! {
        get { return pointee._Onext }
        nonmutating set { pointee._Onext = newValue }
    }
    internal var _Lnext: Edge! {
        get { return pointee._Lnext }
        nonmutating set { pointee._Lnext = newValue }
    }
    internal var _Org: Vertex! {
        get { return pointee._Org }
        nonmutating set { pointee._Org = newValue }
    }
    internal var _Lface: Face! {
        get { return pointee._Lface }
        nonmutating set { pointee._Lface = newValue }
    }
    internal var _winding: Int {
        get { return pointee._winding }
        nonmutating set { pointee._winding = newValue }
    }
    internal var _activeRegion: ActiveRegion! {
        get { return pointee._activeRegion }
        nonmutating set { pointee._activeRegion = newValue }
    }
    
    internal var _Rface: Face! { get { return pointee._Rface } nonmutating set { pointee._Rface = newValue } }
    internal var _Dst: Vertex! { get { return pointee._Dst } nonmutating set { pointee._Dst = newValue } }
    
    internal var _Oprev: Edge! { get { return pointee._Oprev } nonmutating set { pointee._Oprev = newValue } }
    internal var _Lprev: Edge! { get { return pointee._Lprev } nonmutating set { pointee._Lprev = newValue } }
    internal var _Dprev: Edge! { get { return pointee._Dprev } nonmutating set { pointee._Dprev = newValue } }
    internal var _Rprev: Edge! { get { return pointee._Rprev } nonmutating set { pointee._Rprev = newValue } }
    internal var _Dnext: Edge! { get { return pointee._Dnext } nonmutating set { pointee._Dnext = newValue } }
    internal var _Rnext: Edge! { get { return pointee._Rnext } nonmutating set { pointee._Rnext = newValue } }
    
}

extension UnsafeMutablePointer where Pointee == MeshUtils._Vertex {
    var _prev: Vertex! { get { return pointee._prev } nonmutating set { pointee._prev = newValue } }
    var _next: Vertex! { get { return pointee._next } nonmutating set { pointee._next = newValue } }
    var _anEdge: Edge! { get { return pointee._anEdge } nonmutating set { pointee._anEdge = newValue } }
    var _coords: Vector3 { get { return pointee._coords } nonmutating set { pointee._coords = newValue } }
    var _s: Real { get { return pointee._s } nonmutating set { pointee._s = newValue } }
    var _t: Real { get { return pointee._t } nonmutating set { pointee._t = newValue } }
    var _pqHandle: PQHandle { get { return pointee._pqHandle } nonmutating set { pointee._pqHandle = newValue } }
    var _n: Int { get { return pointee._n } nonmutating set { pointee._n = newValue } }
    var _data: Any? { get { return pointee._data } nonmutating set { pointee._data = newValue } }
}

extension UnsafeMutablePointer where Pointee: Linked {
    
    /// Loops over each element, starting from this instance, until
    /// either _next is nil, or the check closure returns false.
    ///
    /// This method captures the next element before calling the closure,
    /// so it's safe to change the element's _next pointer within it.
    func loop(while check: (_ element: UnsafeMutablePointer) throws -> Bool,
              with closure: (_ element: UnsafeMutablePointer) throws -> (Void)) rethrows {
        
        var current: UnsafeMutablePointer<Pointee>! = self
        var next: UnsafeMutablePointer<Pointee>?
        repeat {
            guard let n = current else {
                break
            }
            
            defer {
                current = next
            }
            
            next = n.pointee._next
            try closure(n)
        } while try current != nil && check(current)
    }
    
    /// Iterates over each element, starting from this instance, until
    /// either _next is nil, or _next points to this element.
    ///
    /// This method captures the next element before calling the closure,
    /// so it's safe to change the element's _next pointer within it.
    func loop(with closure: (_ element: UnsafeMutablePointer<Pointee>) throws -> (Void)) rethrows {
        let start = self
        try loop(while: { $0 != start }, with: closure)
    }
}
