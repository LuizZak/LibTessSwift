//
//  MeshUtils.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

import UIKit

public protocol EmptyInitializable {
    init()
}

public struct Vec3: CustomStringConvertible, EmptyInitializable {
    public static var Zero = Vec3()

    public var X: CGFloat, Y: CGFloat, Z: CGFloat

    public subscript(index: Int) -> CGFloat {
        get {
            if (index == 0) { return X }
            if (index == 1) { return Y }
            if (index == 2) { return Z }
            fatalError("out of bounds")
        }
        set {
            if (index == 0) { X = newValue } else if (index == 1) { Y = newValue } else if (index == 2) { Z = newValue }
        }
    }
    
    public init(X: CGFloat, Y: CGFloat, Z: CGFloat) {
        self.X = X
        self.Y = Y
        self.Z = Z
    }
    
    public init() {
        self.X = 0
        self.Y = 0
        self.Z = 0
    }

    public static func Sub(lhs: inout Vec3, rhs: inout Vec3, result: inout Vec3)  {
        result.X = lhs.X - rhs.X
        result.Y = lhs.Y - rhs.Y
        result.Z = lhs.Z - rhs.Z
    }

    public static func Neg(v: inout Vec3) {
        v.X = -v.X
        v.Y = -v.Y
        v.Z = -v.Z
    }

    public static func Dot(u: inout Vec3, v: inout Vec3, dot: inout CGFloat) {
        dot = u.X * v.X + u.Y * v.Y + u.Z * v.Z
    }

    public static func Normalize(v: inout Vec3) {
        
        var len: CGFloat = v.X * v.X + v.Y * v.Y + v.Z * v.Z
        
        assert(len >= 0.0)
        
        len = 1.0 / sqrt(len)
        v.X *= len
        v.Y *= len
        v.Z *= len
    }

    public static func LongAxis(v: inout Vec3) -> Int {
        var i = 0
        if (abs(v.Y) > abs(v.X)) { i = 1 }
        if (abs(v.Z) > abs(i == 0 ? v.X : v.Y)) { i = 2 }
        
        return i
    }

    public var description: String {
        return "\(X), \(Y), \(Z)"
    }
}

public protocol Pooled: EmptyInitializable {
    static func Create() -> Self
    func Reset()
    func OnFree()
    func Free()
}

extension Pooled {
    static func Create() -> Self {
        return Self()
    }
    func OnFree() {
        
    }
    func Free() {
        OnFree()
        Reset()
    }
}

/// Describes an object that is linked to another self
internal protocol Linked: class {
    var _next: Self! { get }
    
    /// Loops over each element, starting from this instance, until
    /// either _next is nil, or the check closure returns false.
    ///
    /// This method captures the next element before calling the closure,
    /// so it's safe to change the element's _next pointer within it.
    func loop(while check: (_ element: Self) throws -> Bool, with closure: (_ element: Self) throws -> (Void)) rethrows
    
    /// Iterates over each element, starting from this instance, until
    /// either _next is nil, or _next points to this element.
    ///
    /// The closure returns a value specifying whether the loop should
    /// be stopped.
    ///
    /// This method captures the next element before calling the closure,
    /// so it's safe to change the element's _next pointer within it.
    func loop(with closure: (_ element: Self) throws -> (Void)) rethrows
}

extension Linked {
    
    func loop(while check: (_ element: Self) throws -> Bool, with closure: (_ element: Self) throws -> (Void)) rethrows {
        var f: Self! = self
        var next: Self?
        repeat {
            guard let n = f else {
                break
            }
            
            defer {
                f = next
            }
            
            next = n._next
            try closure(n)
        } while try check(f)
    }
    
    func loop(with closure: (_ element: Self) throws -> (Void)) rethrows {
        let start = self
        try loop(while: { $0 !== start }, with: closure)
    }
}

internal class MeshUtils {
    
    public static let Undef: Int = ~0
    
    public final class Vertex : Pooled, Linked {
        internal weak var _prev: Vertex!
        internal var _next: Vertex!
        internal var _anEdge: Edge!

        internal var _coords: Vec3 = .Zero
        internal var _s: CGFloat = 0, _t: CGFloat = 0
        internal var _pqHandle: PQHandle = PQHandle()
        internal var _n: Int = 0
        internal var _data: Any?
        
        init() {
            
        }

        public func Reset() {
            _prev = nil
            _next = nil
            _anEdge = nil
            _coords = Vec3.Zero
            _s = 0
            _t = 0
            _pqHandle = PQHandle()
            _n = 0
            _data = nil
        }
    }

    public final class Face : Pooled, Linked {
        internal weak var _prev: Face!
        internal var _next: Face!
        internal var _anEdge: Edge!
        
        internal var _trail: Face?
        internal var _n: Int = 0
        internal var _marked = false, _inside = false

        internal var VertsCount: Int {
            var n = 0
            var eCur = _anEdge
            repeat {
                n += 1
                eCur = eCur?._Lnext
            } while (eCur !== _anEdge)
            return n
        }
        
        init() {
            
        }

        public func Reset() {
            _prev = nil
            _next = nil
            _anEdge = nil
            _trail = nil
            _n = 0
            _marked = false
            _inside = false
        }
    }

    public struct EdgePair {
        internal var _e: Edge?
        internal var _eSym: Edge?

        public static func Create() -> EdgePair {
            var pair = EdgePair()
            pair._e = Edge.Create()
            pair._e?._pair = pair
            pair._eSym = MeshUtils.Edge.Create()
            pair._eSym?._pair = pair
            return pair
        }

        public mutating func Reset() {
            _e = nil
            _eSym = nil
        }
    }

    public final class Edge : Pooled, Linked {
        internal var _pair: EdgePair?
        internal var _next: Edge!, _Sym: Edge!, _Onext: Edge!, _Lnext: Edge!
        internal var _Org: Vertex!
        internal var _Lface: Face!
        internal var _activeRegion: Tess.ActiveRegion!
        internal var _winding: Int = 0

        internal var _Rface: Face! { get { return _Sym?._Lface } set { _Sym?._Lface = newValue } }
        internal var _Dst: Vertex! { get { return _Sym?._Org }  set { _Sym?._Org = newValue } }

        internal var _Oprev: Edge! { get { return _Sym?._Lnext } set { _Sym?._Lnext = newValue } }
        internal var _Lprev: Edge! { get { return _Onext?._Sym } set { _Onext?._Sym = newValue } }
        internal var _Dprev: Edge! { get { return _Lnext?._Sym } set { _Lnext?._Sym = newValue } }
        internal var _Rprev: Edge! { get { return _Sym?._Onext } set { _Sym?._Onext = newValue } }
        internal var _Dnext: Edge! { get { return _Rprev?._Sym } set { _Rprev?._Sym = newValue } }
        internal var _Rnext: Edge! { get { return _Oprev?._Sym } set { _Oprev?._Sym = newValue } }
        
        internal static func EnsureFirst(e: inout Edge) {
            if (e === e._pair?._eSym) {
                e = e._Sym
            }
        }
        
        public init() {
            
        }

        public func Reset() {
            _pair?.Reset()
            _next = nil
            _Sym = nil
            _Onext = nil
            _Lnext = nil
            _Org = nil
            _Lface = nil
            _activeRegion = nil
            _winding = 0
        }
    }

    /// <summary>
    /// MakeEdge creates a new pair of half-edges which form their own loop.
    /// No vertex or face structures are allocated, but these must be assigned
    /// before the current edge operation is completed.
    /// </summary>
    public static func MakeEdge(_ eNext: Edge) -> Edge {
        var eNext = eNext
        
        let pair = EdgePair.Create()
        let e = pair._e
        let eSym = pair._eSym
        
        // Make sure eNext points to the first edge of the edge pair
        Edge.EnsureFirst(e: &eNext)
        
        // Insert in circular doubly-linked list before eNext.
        // Note that the prev pointer is stored in Sym->next.
        let ePrev = eNext._Sym?._next
        eSym?._next = ePrev
        ePrev?._Sym?._next = e
        e?._next = eNext
        eNext._Sym?._next = eSym

        e?._Sym = eSym
        e?._Onext = e
        e?._Lnext = eSym
        e?._Org = nil
        e?._Lface = nil
        e?._winding = 0
        e?._activeRegion = nil

        eSym?._Sym = e
        eSym?._Onext = eSym
        eSym?._Lnext = e
        eSym?._Org = nil
        eSym?._Lface = nil
        eSym?._winding = 0
        eSym?._activeRegion = nil

        return e!
    }

    /// <summary>
    /// Splice( a, b ) is best described by the Guibas/Stolfi paper or the
    /// CS348a notes (see Mesh.cs). Basically it modifies the mesh so that
    /// a->Onext and b->Onext are exchanged. This can have various effects
    /// depending on whether a and b belong to different face or vertex rings.
    /// For more explanation see Mesh.Splice().
    /// </summary>
    public static func Splice(_ a: Edge, _ b: Edge) {
        let aOnext = a._Onext
        let bOnext = b._Onext

        aOnext?._Sym?._Lnext = b
        bOnext?._Sym?._Lnext = a
        a._Onext = bOnext
        b._Onext = aOnext
    }

    /// <summary>
    /// MakeVertex( eOrig, vNext ) attaches a new vertex and makes it the
    /// origin of all edges in the vertex loop to which eOrig belongs. "vNext" gives
    /// a place to insert the new vertex in the global vertex list. We insert
    /// the new vertex *before* vNext so that algorithms which walk the vertex
    /// list will not see the newly created vertices.
    /// </summary>
    public static func MakeVertex(_ eOrig: Edge, _ vNext: Vertex) {
        let vNew = MeshUtils.Vertex.Create()

        // insert in circular doubly-linked list before vNext
        let vPrev = vNext._prev
        vNew._prev = vPrev
        vPrev?._next = vNew
        vNew._next = vNext
        vNext._prev = vNew

        vNew._anEdge = eOrig
        // leave coords, s, t undefined

        // fix other edges on this vertex loop
        var e: Edge? = eOrig
        repeat {
            e?._Org = vNew
            e = e?._Onext
        } while (e !== eOrig)
    }

    /// <summary>
    /// MakeFace( eOrig, fNext ) attaches a new face and makes it the left
    /// face of all edges in the face loop to which eOrig belongs. "fNext" gives
    /// a place to insert the new face in the global face list. We insert
    /// the new face *before* fNext so that algorithms which walk the face
    /// list will not see the newly created faces.
    /// </summary>
    public static func MakeFace(_ eOrig: Edge, _ fNext: Face) {
        let fNew = MeshUtils.Face.Create()

        // insert in circular doubly-linked list before fNext
        let fPrev = fNext._prev
        fNew._prev = fPrev
        fPrev?._next = fNew
        fNew._next = fNext
        fNext._prev = fNew

        fNew._anEdge = eOrig
        fNew._trail = nil
        fNew._marked = false

        // The new face is marked "inside" if the old one was. This is a
        // convenience for the common case where a face has been split in two.
        fNew._inside = fNext._inside

        // fix other edges on this face loop
        var e: Edge? = eOrig
        repeat {
            e?._Lface = fNew
            e = e?._Lnext
        } while (e !== eOrig)
    }

    /// <summary>
    /// KillEdge( eDel ) destroys an edge (the half-edges eDel and eDel->Sym),
    /// and removes from the global edge list.
    /// </summary>
    public static func KillEdge(_ eDel: Edge) {
        // Half-edges are allocated in pairs, see EdgePair above
        var eDel = eDel
        Edge.EnsureFirst(e: &eDel)

        // delete from circular doubly-linked list
        let eNext = eDel._next
        let ePrev = eDel._Sym?._next
        eNext?._Sym?._next = ePrev
        ePrev?._Sym?._next = eNext

        eDel.Free()
    }

    /// <summary>
    /// KillVertex( vDel ) destroys a vertex and removes it from the global
    /// vertex list. It updates the vertex loop to point to a given new vertex.
    /// </summary>
    public static func KillVertex(_ vDel: Vertex, _ newOrg: Vertex?) {
        let eStart = vDel._anEdge

        // change the origin of all affected edges
        var e: Edge? = eStart
        repeat {
            e?._Org = newOrg
            e = e?._Onext
        } while (e !== eStart)

        // delete from circular doubly-linked list
        let vPrev = vDel._prev
        let vNext = vDel._next
        vNext?._prev = vPrev
        vPrev?._next = vNext

        vDel.Free()
    }

    /// <summary>
    /// KillFace( fDel ) destroys a face and removes it from the global face
    /// list. It updates the face loop to point to a given new face.
    /// </summary>
    public static func KillFace(_ fDel: Face, _ newLFace: Face?) {
        let eStart = fDel._anEdge

        // change the left face of all affected edges
        var e: Edge? = eStart
        repeat {
            e?._Lface = newLFace
            e = e?._Lnext
        } while (e !== eStart)

        // delete from circular doubly-linked list
        let fPrev = fDel._prev
        let fNext = fDel._next
        fNext?._prev = fPrev
        fPrev?._next = fNext

        fDel.Free()
    }

    /// <summary>
    /// Return signed area of face.
    /// </summary>
    public static func FaceArea(_ f: Face) -> CGFloat {
        var area: CGFloat = 0
        var e = f._anEdge!
        repeat {
            area += (e._Org._s - e._Dst._s) * (e._Org._t + e._Dst._t)
            e = e._Lnext!
        } while (e !== f._anEdge)
        return area
    }
}
