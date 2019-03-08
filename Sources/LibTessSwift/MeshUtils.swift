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
#else
public typealias Real = Float
#endif

public struct Vector3 {
    public static let zero = Vector3()
    
    public subscript(_ i: Int) -> Real {
        get {
            switch i {
            case 0:
                return x
            case 1:
                return y
            case 2:
                return z
            default:
                fatalError("Invalid subscription index \(i)")
            }
        }
        set {
            switch i {
            case 0:
                x = newValue
            case 1:
                y = newValue
            case 2:
                z = newValue
            default:
                fatalError("Invalid subscription index \(i)")
            }
        }
    }
    
    public var x: Real
    public var y: Real
    public var z: Real
    
    public init(x: Real, y: Real, z: Real) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    public init() {
        self.x = 0
        self.y = 0
        self.z = 0
    }
    
    public static func longAxis(v: inout Vector3) -> Int {
        var i = 0
        if abs(v.y) > abs(v.x) { i = 1 }
        if abs(v.z) > abs(i == 0 ? v.x : v.y) { i = 2 }
        
        return i
    }
    
    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        return Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
    
    public static prefix func - (value: Vector3) -> Vector3 {
        return Vector3(x: -value.x, y: -value.y, z: -value.z)
    }
}

public func dot(_ lhs: Vector3, _ rhs: Vector3) -> Real {
    return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

/// Describes an object that can be chained with other instances of itself
/// indefinitely. This also supports looped links that point circularly.
internal protocol Linked {
    var _next: UnsafeMutablePointer<Self>? { get }
}

internal class MeshUtils {
    
    static let Undef: Int = ~0
    
    struct _Vertex: Linked, EmptyInitializable {
        internal var _prev: Vertex!
        internal var _next: Vertex?
        internal var _anEdge: Edge!

        internal var _coords: Vector3 = .zero
        internal var _s: Real = 0, _t: Real = 0
        internal var _pqHandle: PQHandle = PQHandle()
        internal var _n: Int = 0
        internal var _data: Any?
        
        init() {
            
        }
    }

    struct _Face: Linked, EmptyInitializable {
        internal var _prev: Face!
        internal var _next: Face?
        internal var _anEdge: Edge!
        
        internal var _n: Int = 0
        internal var _marked = false, _inside = false

        internal var vertsCount: Int {
            var n = 0
            var eCur = _anEdge
            repeat {
                n += 1
                eCur = eCur?.Lnext
            } while eCur != _anEdge
            return n
        }
        
        init() {
            
        }
    }

    struct EdgePair {
        internal var _e: Edge?
        internal var _eSym: Edge?
    }

    struct _Edge: Linked, EmptyInitializable {
        internal var _pair: EdgePair?
        internal var _next: Edge?
        internal var _sym: Edge!
        internal var _Onext: Edge!
        internal var _Lnext: Edge!
        internal var _Org: Vertex!
        internal var _Lface: Face!
        internal var _activeRegion: ActiveRegion!
        internal var _winding: Int = 0

        internal var _Rface: Face! { get { return _sym.Lface } set { _sym.Lface = newValue } }
        internal var _Dst: Vertex! { get { return _sym.Org }  set { _sym.Org = newValue } }

        internal var _Oprev: Edge! { get { return _sym.Lnext } set { _sym.Lnext = newValue } }
        internal var _Lprev: Edge! { get { return _Onext.sym } set { _Onext.sym = newValue } }
        internal var _Dprev: Edge! { get { return _Lnext.sym } set { _Lnext.sym = newValue } }
        internal var _Rprev: Edge! { get { return _sym.Onext } set { _sym.Onext = newValue } }
        internal var _Dnext: Edge! { get { return _Rprev?.sym } set { _Rprev?.sym = newValue } }
        internal var _Rnext: Edge! { get { return _Oprev?.sym } set { _Oprev?.sym = newValue } }
        
        internal static func ensureFirst(e: inout Edge) {
            if e == e.pair?._eSym {
                e = e.sym
            }
        }
        
        init() {
            
        }
    }
    
    /// <summary>
    /// splice( a, b ) is best described by the Guibas/Stolfi paper or the
    /// CS348a notes (see Mesh.cs). Basically it modifies the mesh so that
    /// a->Onext and b->Onext are exchanged. This can have various effects
    /// depending on whether a and b belong to different face or vertex rings.
    /// For more explanation see Mesh.splice().
    /// </summary>
    static func splice(_ a: Edge, _ b: Edge) {
        let aOnext = a.Onext
        let bOnext = b.Onext
        
        aOnext?.sym.Lnext = b
        bOnext?.sym.Lnext = a
        a.Onext = bOnext
        b.Onext = aOnext
    }
    
    /// <summary>
    /// Return signed area of face.
    /// </summary>
    static func faceArea(_ f: Face) -> Real {
        var area: Real = 0
        
        var e = f.anEdge!
        repeat {
            area += (e.Org.s - e.Dst.s) * (e.Org.t + e.Dst.t)
            e = e.Lnext
        } while e != f.anEdge
        return area
    }
}

// Pointers of primitives
typealias Face = UnsafeMutablePointer<MeshUtils._Face>
typealias Edge = UnsafeMutablePointer<MeshUtils._Edge>
typealias Vertex = UnsafeMutablePointer<MeshUtils._Vertex>

// Shortcuts for pointers of primitives
extension UnsafeMutablePointer where Pointee == MeshUtils._Face {
    var prev: Face! {
        get { return pointee._prev }
        nonmutating set { pointee._prev = newValue }
    }
    var next: Face! {
        get { return pointee._next }
        nonmutating set { pointee._next = newValue }
    }
    var anEdge: Edge! {
        get { return pointee._anEdge }
        nonmutating set { pointee._anEdge = newValue }
    }
    
    var VertsCount: Int {
        return pointee.vertsCount
    }
    
    var n: Int {
        get { return pointee._n }
        nonmutating set { pointee._n = newValue }
    }
    
    var marked: Bool {
        get { return pointee._marked }
        nonmutating set { pointee._marked = newValue }
    }
    var inside: Bool {
        get { return pointee._inside }
        nonmutating set { pointee._inside = newValue }
    }
}

extension UnsafeMutablePointer where Pointee == MeshUtils._Edge {
    internal var pair: MeshUtils.EdgePair? {
        get { return pointee._pair }
        nonmutating set { return pointee._pair = newValue }
    }
    internal var next: Edge! {
        get { return pointee._next }
        nonmutating set { pointee._next = newValue }
    }
    internal var sym: Edge! {
        get {
            return pointee._sym
        }
        nonmutating set {
            pointee._sym = newValue
        }
    }
    internal var Onext: Edge! {
        get { return pointee._Onext }
        nonmutating set { pointee._Onext = newValue }
    }
    internal var Lnext: Edge! {
        get { return pointee._Lnext }
        nonmutating set { pointee._Lnext = newValue }
    }
    internal var Org: Vertex! {
        get { return pointee._Org }
        nonmutating set { pointee._Org = newValue }
    }
    internal var Lface: Face! {
        get { return pointee._Lface }
        nonmutating set { pointee._Lface = newValue }
    }
    internal var winding: Int {
        get { return pointee._winding }
        nonmutating set { pointee._winding = newValue }
    }
    internal var activeRegion: ActiveRegion! {
        get { return pointee._activeRegion }
        nonmutating set { pointee._activeRegion = newValue }
    }
    
    internal var Rface: Face! { get { return pointee._Rface } nonmutating set { pointee._Rface = newValue } }
    internal var Dst: Vertex! { get { return pointee._Dst } nonmutating set { pointee._Dst = newValue } }
    
    internal var Oprev: Edge! { get { return pointee._Oprev } nonmutating set { pointee._Oprev = newValue } }
    internal var Lprev: Edge! { get { return pointee._Lprev } nonmutating set { pointee._Lprev = newValue } }
    internal var Dprev: Edge! { get { return pointee._Dprev } nonmutating set { pointee._Dprev = newValue } }
    internal var Rprev: Edge! { get { return pointee._Rprev } nonmutating set { pointee._Rprev = newValue } }
    internal var Dnext: Edge! { get { return pointee._Dnext } nonmutating set { pointee._Dnext = newValue } }
    internal var Rnext: Edge! { get { return pointee._Rnext } nonmutating set { pointee._Rnext = newValue } }
}

extension UnsafeMutablePointer where Pointee == MeshUtils._Vertex {
    var prev: Vertex! { get { return pointee._prev } nonmutating set { pointee._prev = newValue } }
    var next: Vertex! { get { return pointee._next } nonmutating set { pointee._next = newValue } }
    var anEdge: Edge! { get { return pointee._anEdge } nonmutating set { pointee._anEdge = newValue } }
    var coords: Vector3 { get { return pointee._coords } nonmutating set { pointee._coords = newValue } }
    var s: Real { get { return pointee._s } nonmutating set { pointee._s = newValue } }
    var t: Real { get { return pointee._t } nonmutating set { pointee._t = newValue } }
    var pqHandle: PQHandle { get { return pointee._pqHandle } nonmutating set { pointee._pqHandle = newValue } }
    var n: Int { get { return pointee._n } nonmutating set { pointee._n = newValue } }
    var data: Any? { get { return pointee._data } nonmutating set { pointee._data = newValue } }
}

extension UnsafeMutablePointer where Pointee: Linked {
    
    /// Loops over each element, starting from this instance, until
    /// either _next is nil, or the check closure returns false.
    ///
    /// This method captures the next element before calling the closure,
    /// so it's safe to change the element's _next pointer within it.
    func loop(while check: (_ element: UnsafeMutablePointer) throws -> Bool,
              with closure: (_ element: UnsafeMutablePointer) throws -> (Void)) rethrows {
        
        var current = self
        var next: UnsafeMutablePointer<Pointee>?
        repeat {
            next = current.pointee._next
            try closure(current)
            
            if let next = next {
                current = next
            } else {
                break
            }
        } while try check(current)
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
