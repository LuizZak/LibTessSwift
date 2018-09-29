//
//  Mesh.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

internal final class Mesh {
    
    internal var _vHead: Vertex
    internal var _fHead: Face
    internal var _eHead: Edge
    internal var _eHeadSym: Edge?
    
    internal var _context = MeshCreationContext()

    init() {
        let v = _context.createVertex()
        _vHead = v
        let f = _context.createFace()
        _fHead = f
        
        let (_, e, eSym) = _context.createEdgePair()
        _eHead = e
        _eHeadSym = eSym
        
        v._next = v
        v._prev = v
        
        f._next = f
        f._prev = f
        
        e._next = e
        e._Sym = eSym

        eSym._next = eSym
        eSym._Sym = e
    }
    
    deinit {
        free()
    }
    
    public func free() {
        _context.free()
    }
    
    /// Loops all the faces of this mesh with a given closure.
    /// Looping is safe to modify the face's _next pointer, so long as it does
    /// not modify the next's.
    public func forEachFace(with closure: (Face) throws -> Void) rethrows {
        try _fHead._next?.loop(while: { $0 != _fHead }, with: closure)
    }
    
    /// Loops all the vertices of this mesh with a given closure.
    /// Looping is safe to modify the vertex's _next pointer, so long as it does
    /// not modify the next's.
    public func forEachVertex(with closure: (Vertex) throws -> Void) rethrows {
        try _vHead._next?.loop(while: { $0 != _vHead }, with: closure)
    }
    
    /// Loops all the edges of this mesh with a given closure.
    /// Looping is safe to modify the vertex's _next pointer, so long as it does
    /// not modify the next's.
    public func forEachEdge(with closure: (Edge) throws -> Void) rethrows {
        try _eHead._next?.loop(while: { $0 != _eHead }, with: closure)
    }
    
    /// <summary>
    /// Creates one edge, two vertices and a loop (face).
    /// The loop consists of the two new half-edges.
    /// </summary>
    public func makeEdge() -> Edge {
        let e = _context.MakeEdge(_eHead)
        
        _context.makeVertex(e, _vHead)
        _context.makeVertex(e._Sym, _vHead)
        _context.makeFace(e, _fHead)
    
        return e
    }
    
    /// <summary>
    /// Splice is the basic operation for changing the
    /// mesh connectivity and topology.  It changes the mesh so that
    ///     eOrg->Onext = OLD( eDst->Onext )
    ///     eDst->Onext = OLD( eOrg->Onext )
    /// where OLD(...) means the value before the meshSplice operation.
    /// 
    /// This can have two effects on the vertex structure:
    ///  - if eOrg->Org != eDst->Org, the two vertices are merged together
    ///  - if eOrg->Org == eDst->Org, the origin is split into two vertices
    /// In both cases, eDst->Org is changed and eOrg->Org is untouched.
    /// 
    /// Similarly (and independently) for the face structure,
    ///  - if eOrg->Lface == eDst->Lface, one loop is split into two
    ///  - if eOrg->Lface != eDst->Lface, two distinct loops are joined into one
    /// In both cases, eDst->Lface is changed and eOrg->Lface is unaffected.
    /// 
    /// Some special cases:
    /// If eDst == eOrg, the operation has no effect.
    /// If eDst == eOrg->Lnext, the new face will have a single edge.
    /// If eDst == eOrg->Lprev, the old face will have a single edge.
    /// If eDst == eOrg->Onext, the new vertex will have a single edge.
    /// If eDst == eOrg->Oprev, the old vertex will have a single edge.
    /// </summary>
    public func splice(_ eOrg: Edge, _ eDst: Edge) {
        if (eOrg == eDst) {
            return
        }

        var joiningVertices = false
        if (eDst._Org != eOrg._Org) {
            // We are merging two disjoint vertices -- destroy eDst->Org
            joiningVertices = true
            _context.killVertex(eDst._Org!, eOrg._Org!)
        }
        var joiningLoops = false
        if (eDst._Lface != eOrg._Lface) {
            // We are connecting two disjoint loops -- destroy eDst->Lface
            joiningLoops = true
            _context.killFace(eDst._Lface, eOrg._Lface)
        }

        // Change the edge structure
        MeshUtils.splice(eDst, eOrg)

        if (!joiningVertices) {
            // We split one vertex into two -- the new vertex is eDst->Org.
            // Make sure the old vertex points to a valid half-edge.
            _context.makeVertex(eDst, eOrg._Org!)
            eOrg._Org?._anEdge = eOrg
        }
        if (!joiningLoops) {
            // We split one loop into two -- the new loop is eDst->Lface.
            // Make sure the old face points to a valid half-edge.
            _context.makeFace(eDst, eOrg._Lface)
            eOrg._Lface._anEdge = eOrg
        }
    }

    /// <summary>
    /// Removes the edge eDel. There are several cases:
    /// if (eDel->Lface != eDel->Rface), we join two loops into one; the loop
    /// eDel->Lface is deleted. Otherwise, we are splitting one loop into two
    /// the newly created loop will contain eDel->Dst. If the deletion of eDel
    /// would create isolated vertices, those are deleted as well.
    /// </summary>
    public func delete(_ eDel: Edge) {
        let eDelSym = eDel._Sym!
        
        // First step: disconnect the origin vertex eDel->Org.  We make all
        // changes to get a consistent mesh in this "intermediate" state.
        
        var joiningLoops = false
        if (eDel._Lface != eDel._Rface) {
            // We are joining two loops into one -- remove the left face
            joiningLoops = true
            _context.killFace(eDel._Lface, eDel._Rface!)
        }

        if (eDel._Onext == eDel) {
            _context.killVertex(eDel._Org!, nil)
        } else {
            // Make sure that eDel->Org and eDel->Rface point to valid half-edges
            eDel._Rface?._anEdge = eDel._Oprev
            eDel._Org?._anEdge = eDel._Onext

            MeshUtils.splice(eDel, eDel._Oprev!)

            if (!joiningLoops) {
                // We are splitting one loop into two -- create a new loop for eDel.
                _context.makeFace(eDel, eDel._Lface)
            }
        }

        // Claim: the mesh is now in a consistent state, except that eDel->Org
        // may have been deleted.  Now we disconnect eDel->Dst.

        if (eDelSym._Onext == eDelSym) {
            _context.killVertex(eDelSym._Org!, nil)
            _context.killFace(eDelSym._Lface, nil)
        } else {
            // Make sure that eDel->Dst and eDel->Lface point to valid half-edges
            eDel._Lface._anEdge = eDelSym._Oprev
            eDelSym._Org._anEdge = eDelSym._Onext
            MeshUtils.splice(eDelSym, eDelSym._Oprev!)
        }

        // Any isolated vertices or faces have already been freed.
        _context.killEdge(eDel)
    }

    /// <summary>
    /// Creates a new edge such that eNew == eOrg.Lnext and eNew.Dst is a newly created vertex.
    /// eOrg and eNew will have the same left face.
    /// </summary>
    @discardableResult
    public func addEdgeVertex(_ eOrg: Edge) -> Edge {
        let eNew = _context.MakeEdge(eOrg)
        let eNewSym = eNew._Sym!

        // Connect the new edge appropriately
        MeshUtils.splice(eNew, eOrg._Lnext)

        // Set vertex and face information
        eNew._Org = eOrg._Dst
        _context.makeVertex(eNewSym, eNew._Org)
        eNew._Lface = eOrg._Lface
        eNewSym._Lface = eOrg._Lface

        return eNew
    }

    /// <summary>
    /// Splits eOrg into two edges eOrg and eNew such that eNew == eOrg.Lnext.
    /// The new vertex is eOrg.Dst == eNew.Org.
    /// eOrg and eNew will have the same left face.
    /// </summary>
    @discardableResult
    public func splitEdge(_ eOrg: Edge) -> Edge {
        let eTmp = addEdgeVertex(eOrg)
        let eNew = eTmp._Sym!

        // Disconnect eOrg from eOrg->Dst and connect it to eNew->Org
        MeshUtils.splice(eOrg._Sym, eOrg._Sym._Oprev)
        MeshUtils.splice(eOrg._Sym, eNew)

        // Set the vertex and face information
        eOrg._Dst = eNew._Org
        eNew._Dst._anEdge = eNew._Sym // may have pointed to eOrg->Sym
        eNew._Rface = eOrg._Rface
        eNew._winding = eOrg._winding // copy old winding information
        eNew._Sym._winding = eOrg._Sym._winding

        return eNew
    }

    /// <summary>
    /// Creates a new edge from eOrg->Dst to eDst->Org, and returns the corresponding half-edge eNew.
    /// If eOrg->Lface == eDst->Lface, this splits one loop into two,
    /// and the newly created loop is eNew->Lface.  Otherwise, two disjoint
    /// loops are merged into one, and the loop eDst->Lface is destroyed.
    /// 
    /// If (eOrg == eDst), the new face will have only two edges.
    /// If (eOrg->Lnext == eDst), the old face is reduced to a single edge.
    /// If (eOrg->Lnext->Lnext == eDst), the old face is reduced to two edges.
    /// </summary>
    @discardableResult
    public func connect(_ eOrg: Edge, _ eDst: Edge) -> Edge {
        let eNew = _context.MakeEdge(eOrg)
        let eNewSym = eNew._Sym!

        var joiningLoops = false
        if (eDst._Lface != eOrg._Lface) {
            // We are connecting two disjoint loops -- destroy eDst->Lface
            joiningLoops = true
            _context.killFace(eDst._Lface, eOrg._Lface)
        }
        
        // Connect the new edge appropriately
        MeshUtils.splice(eNew, eOrg._Lnext)
        MeshUtils.splice(eNewSym, eDst)

        // Set the vertex and face information
        eNew._Org = eOrg._Dst
        eNewSym._Org = eDst._Org
        eNew._Lface = eOrg._Lface
        eNewSym._Lface = eOrg._Lface

        // Make sure the old face points to a valid half-edge
        eOrg._Lface._anEdge = eNewSym

        if (!joiningLoops) {
            _context.makeFace(eNew, eOrg._Lface)
        }

        return eNew
    }

    /// <summary>
    /// Destroys a face and removes it from the global face list. All edges of
    /// fZap will have a nil pointer as their left face. Any edges which
    /// also have a nil pointer as their right face are deleted entirely
    /// (along with any isolated vertices this produces).
    /// An entire mesh can be deleted by zapping its faces, one at a time,
    /// in any order. Zapped faces cannot be used in further mesh operations!
    /// </summary>
    public func zapFace(_ fZap: Face) {
        let eStart = fZap._anEdge!

        // walk around face, deleting edges whose right face is also nil
        var eNext: Edge = eStart._Lnext
        var e: Edge, eSym: Edge
        repeat {
            e = eNext
            eNext = e._Lnext

            e._Lface = nil
            if (e._Rface != nil) {
                continue
            }
            
            // delete the edge -- see TESSmeshDelete above

            if (e._Onext == e) {
                _context.killVertex(e._Org!, nil)
            } else {
                // Make sure that e._Org points to a valid half-edge
                e._Org!._anEdge = e._Onext
                MeshUtils.splice(e, e._Oprev)
            }
            eSym = e._Sym
            if (eSym._Onext == eSym) {
                _context.killVertex(eSym._Org!, nil)
            } else {
                // Make sure that eSym._Org points to a valid half-edge
                eSym._Org!._anEdge = eSym._Onext
                MeshUtils.splice(eSym, eSym._Oprev)
            }
            _context.killEdge(e)
        } while (e != eStart)

        /* delete from circular doubly-linked list */
        let fPrev = fZap._prev
        let fNext = fZap._next
        fNext!._prev = fPrev
        fPrev!._next = fNext
        
        _context.resetFace(fZap)
    }

    public func mergeConvexFaces(maxVertsPerFace: Int) {
        forEachFace { f in
            // Skip faces which are outside the result
            if (!f._inside) {
                return
            }
            
            var eCur: Edge! = f._anEdge!
            let vStart = eCur._Org
            
            while (true) {
                var eNext = eCur._Lnext
                
                defer {
                    // Continue to the next edge
                    eCur = eNext
                }
                
                let eSym: Edge! = eCur._Sym
                
                if eSym != nil && eSym._Lface != nil && eSym._Lface._inside {
                    // Try to merge the neighbour faces if the resulting polygons
                    // does not exceed maximum number of vertices.
                    let curNv = f.VertsCount
                    let symNv = eSym._Lface.VertsCount
                    if ((curNv + symNv - 2) <= maxVertsPerFace) {
                        // Merge if the resulting poly is convex.
                        if (Geom.vertCCW(eCur._Lprev!._Org!, eCur._Org!, eSym._Lnext._Lnext._Org!) &&
                            Geom.vertCCW(eSym._Lprev!._Org!, eSym._Org!, eCur._Lnext._Lnext._Org!)) {
                            eNext = eSym._Lnext
                            delete(eSym)
                            eCur = nil
                        }
                    }
                }
                
                if (eCur != nil && eCur._Lnext._Org == vStart) {
                    break
                }
            }
        }
    }
    
    public func check() {
        // Loops backwards across edges, faces and vertices of this mesh, make
        // sure everything is tidy and correctly set.
        var e: Edge
        
        var fPrev = _fHead
        var f = _fHead
        
        while fPrev._next != _fHead
        {
            defer {
                fPrev = f
            }
            
            f = fPrev._next
            
            e = f._anEdge
            repeat {
                assert(e._Sym != e)
                assert(e._Sym._Sym == e)
                assert(e._Lnext._Onext._Sym == e)
                assert(e._Onext._Sym._Lnext == e)
                assert(e._Lface == f)
                e = e._Lnext
            } while (e != f._anEdge)
        }
        
        f = fPrev._next
        
        assert(f._prev == fPrev && f._anEdge == nil)
        
        var vPrev = _vHead
        var v = _vHead
        
        while vPrev._next != _vHead
        {
            defer {
                vPrev = v
            }
            
            v = vPrev._next
            
            assert(v._prev == vPrev)
            e = v._anEdge
            repeat {
                assert(e._Sym != e)
                assert(e._Sym._Sym == e)
                assert(e._Lnext._Onext._Sym == e)
                assert(e._Onext._Sym._Lnext == e)
                assert(e._Org == v)
                e = e._Onext
            } while (e != v._anEdge)
        }
        
        v = vPrev._next
        
        assert(v._prev == vPrev && v._anEdge == nil)
        
        var ePrev = _eHead
        e = _eHead
        
        while ePrev._next != _eHead
        {
            defer {
                ePrev = e
            }
            
            e = ePrev._next
            
            assert(e._Sym._next == ePrev._Sym)
            assert(e._Sym != e)
            assert(e._Sym._Sym == e)
            assert(e._Org != nil)
            assert(e._Dst != nil)
            assert(e._Lnext._Onext._Sym == e)
            assert(e._Onext._Sym._Lnext == e)
        }
        
        e = ePrev._next
        
        assert(e._Sym._next == ePrev._Sym)
        assert(e._Sym == _eHeadSym)
        assert(e._Sym._Sym == e)
        assert(e._Org == nil)
        assert(e._Dst == nil)
        assert(e._Lface == nil)
        assert(e._Rface == nil)
    }
}
