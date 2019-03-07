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
    
    internal var _context: MeshCreationContext

    init(context: MeshCreationContext) {
        self._context = context
        
        let v = _context.createVertex()
        _vHead = v
        let f = _context.createFace()
        _fHead = f
        
        let (_, e, eSym) = _context.createEdgePair()
        _eHead = e
        _eHeadSym = eSym
        
        v.next = v
        v.prev = v
        
        f.next = f
        f.prev = f
        
        e.next = e
        e.Sym = eSym

        eSym.next = eSym
        eSym.Sym = e
    }
    
    deinit {
        free()
    }
    
    func free() {
        // Do nothing, for now; mesh context is cleaned by clients of this class.
    }
    
    /// Loops all the faces of this mesh with a given closure.
    /// Looping is safe to modify the face's _next pointer, so long as it does
    /// not modify the next's.
    func forEachFace(with closure: (Face) throws -> Void) rethrows {
        try _fHead.next?.loop(while: { $0 != _fHead }, with: closure)
    }
    
    /// Loops all the vertices of this mesh with a given closure.
    /// Looping is safe to modify the vertex's _next pointer, so long as it does
    /// not modify the next's.
    func forEachVertex(with closure: (Vertex) throws -> Void) rethrows {
        try _vHead.next?.loop(while: { $0 != _vHead }, with: closure)
    }
    
    /// Loops all the edges of this mesh with a given closure.
    /// Looping is safe to modify the vertex's _next pointer, so long as it does
    /// not modify the next's.
    func forEachEdge(with closure: (Edge) throws -> Void) rethrows {
        try _eHead.next?.loop(while: { $0 != _eHead }, with: closure)
    }
    
    /// <summary>
    /// Creates one edge, two vertices and a loop (face).
    /// The loop consists of the two new half-edges.
    /// </summary>
    func makeEdge() -> Edge {
        let e = _context.makeEdge(_eHead)
        
        _context.makeVertex(e, _vHead)
        _context.makeVertex(e.Sym, _vHead)
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
    func splice(_ eOrg: Edge, _ eDst: Edge) {
        if (eOrg == eDst) {
            return
        }

        var joiningVertices = false
        if (eDst.Org != eOrg.Org) {
            // We are merging two disjoint vertices -- destroy eDst->Org
            joiningVertices = true
            _context.killVertex(eDst.Org!, eOrg.Org!)
        }
        var joiningLoops = false
        if (eDst.Lface != eOrg.Lface) {
            // We are connecting two disjoint loops -- destroy eDst->Lface
            joiningLoops = true
            _context.killFace(eDst.Lface, eOrg.Lface)
        }

        // Change the edge structure
        MeshUtils.splice(eDst, eOrg)

        if (!joiningVertices) {
            // We split one vertex into two -- the new vertex is eDst->Org.
            // Make sure the old vertex points to a valid half-edge.
            _context.makeVertex(eDst, eOrg.Org!)
            eOrg.Org?.anEdge = eOrg
        }
        if (!joiningLoops) {
            // We split one loop into two -- the new loop is eDst->Lface.
            // Make sure the old face points to a valid half-edge.
            _context.makeFace(eDst, eOrg.Lface)
            eOrg.Lface.anEdge = eOrg
        }
    }

    /// <summary>
    /// Removes the edge eDel. There are several cases:
    /// if (eDel->Lface != eDel->Rface), we join two loops into one; the loop
    /// eDel->Lface is deleted. Otherwise, we are splitting one loop into two
    /// the newly created loop will contain eDel->Dst. If the deletion of eDel
    /// would create isolated vertices, those are deleted as well.
    /// </summary>
    func delete(_ eDel: Edge) {
        let eDelSym = eDel.Sym!
        
        // First step: disconnect the origin vertex eDel->Org.  We make all
        // changes to get a consistent mesh in this "intermediate" state.
        
        var joiningLoops = false
        if (eDel.Lface != eDel.Rface) {
            // We are joining two loops into one -- remove the left face
            joiningLoops = true
            _context.killFace(eDel.Lface, eDel.Rface!)
        }

        if (eDel.Onext == eDel) {
            _context.killVertex(eDel.Org!, nil)
        } else {
            // Make sure that eDel->Org and eDel->Rface point to valid half-edges
            eDel.Rface?.anEdge = eDel.Oprev
            eDel.Org?.anEdge = eDel.Onext

            MeshUtils.splice(eDel, eDel.Oprev!)

            if (!joiningLoops) {
                // We are splitting one loop into two -- create a new loop for eDel.
                _context.makeFace(eDel, eDel.Lface)
            }
        }

        // Claim: the mesh is now in a consistent state, except that eDel->Org
        // may have been deleted.  Now we disconnect eDel->Dst.

        if (eDelSym.Onext == eDelSym) {
            _context.killVertex(eDelSym.Org!, nil)
            _context.killFace(eDelSym.Lface, nil)
        } else {
            // Make sure that eDel->Dst and eDel->Lface point to valid half-edges
            eDel.Lface.anEdge = eDelSym.Oprev
            eDelSym.Org.anEdge = eDelSym.Onext
            MeshUtils.splice(eDelSym, eDelSym.Oprev!)
        }

        // Any isolated vertices or faces have already been freed.
        _context.killEdge(eDel)
    }

    /// <summary>
    /// Creates a new edge such that eNew == eOrg.Lnext and eNew.Dst is a newly created vertex.
    /// eOrg and eNew will have the same left face.
    /// </summary>
    @discardableResult
    func addEdgeVertex(_ eOrg: Edge) -> Edge {
        let eNew = _context.makeEdge(eOrg)
        let eNewSym = eNew.Sym!

        // Connect the new edge appropriately
        MeshUtils.splice(eNew, eOrg.Lnext)

        // Set vertex and face information
        eNew.Org = eOrg.Dst
        _context.makeVertex(eNewSym, eNew.Org)
        eNew.Lface = eOrg.Lface
        eNewSym.Lface = eOrg.Lface

        return eNew
    }

    /// <summary>
    /// Splits eOrg into two edges eOrg and eNew such that eNew == eOrg.Lnext.
    /// The new vertex is eOrg.Dst == eNew.Org.
    /// eOrg and eNew will have the same left face.
    /// </summary>
    @discardableResult
    func splitEdge(_ eOrg: Edge) -> Edge {
        let eTmp = addEdgeVertex(eOrg)
        let eNew = eTmp.Sym!

        // Disconnect eOrg from eOrg->Dst and connect it to eNew->Org
        MeshUtils.splice(eOrg.Sym, eOrg.Sym.Oprev)
        MeshUtils.splice(eOrg.Sym, eNew)

        // Set the vertex and face information
        eOrg.Dst = eNew.Org
        eNew.Dst.anEdge = eNew.Sym // may have pointed to eOrg->Sym
        eNew.Rface = eOrg.Rface
        eNew.winding = eOrg.winding // copy old winding information
        eNew.Sym.winding = eOrg.Sym.winding

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
    func connect(_ eOrg: Edge, _ eDst: Edge) -> Edge {
        let eNew = _context.makeEdge(eOrg)
        let eNewSym = eNew.Sym!

        var joiningLoops = false
        if (eDst.Lface != eOrg.Lface) {
            // We are connecting two disjoint loops -- destroy eDst->Lface
            joiningLoops = true
            _context.killFace(eDst.Lface, eOrg.Lface)
        }
        
        // Connect the new edge appropriately
        MeshUtils.splice(eNew, eOrg.Lnext)
        MeshUtils.splice(eNewSym, eDst)

        // Set the vertex and face information
        eNew.Org = eOrg.Dst
        eNewSym.Org = eDst.Org
        eNew.Lface = eOrg.Lface
        eNewSym.Lface = eOrg.Lface

        // Make sure the old face points to a valid half-edge
        eOrg.Lface.anEdge = eNewSym

        if (!joiningLoops) {
            _context.makeFace(eNew, eOrg.Lface)
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
    func zapFace(_ fZap: Face) {
        let eStart = fZap.anEdge!

        // walk around face, deleting edges whose right face is also nil
        var eNext: Edge = eStart.Lnext
        var e: Edge, eSym: Edge
        repeat {
            e = eNext
            eNext = e.Lnext

            e.Lface = nil
            if (e.Rface != nil) {
                continue
            }
            
            // delete the edge -- see TESSmeshDelete above

            if (e.Onext == e) {
                _context.killVertex(e.Org!, nil)
            } else {
                // Make sure that e.Org points to a valid half-edge
                e.Org!.anEdge = e.Onext
                MeshUtils.splice(e, e.Oprev)
            }
            eSym = e.Sym
            if (eSym.Onext == eSym) {
                _context.killVertex(eSym.Org!, nil)
            } else {
                // Make sure that eSym.Org points to a valid half-edge
                eSym.Org!.anEdge = eSym.Onext
                MeshUtils.splice(eSym, eSym.Oprev)
            }
            _context.killEdge(e)
        } while (e != eStart)

        /* delete from circular doubly-linked list */
        let fPrev = fZap.prev
        let fNext = fZap.next
        fNext!.prev = fPrev
        fPrev!.next = fNext
        
        _context.resetFace(fZap)
    }

    func mergeConvexFaces(maxVertsPerFace: Int) {
        forEachFace { f in
            // Skip faces which are outside the result
            if (!f.inside) {
                return
            }
            
            var eCur: Edge! = f.anEdge!
            let vStart = eCur.Org
            
            while (true) {
                var eNext = eCur.Lnext
                
                defer {
                    // Continue to the next edge
                    eCur = eNext
                }
                
                let eSym: Edge! = eCur.Sym
                
                if eSym != nil && eSym.Lface != nil && eSym.Lface.inside {
                    // Try to merge the neighbour faces if the resulting polygons
                    // does not exceed maximum number of vertices.
                    let curNv = f.VertsCount
                    let symNv = eSym.Lface.VertsCount
                    if ((curNv + symNv - 2) <= maxVertsPerFace) {
                        // Merge if the resulting poly is convex.
                        if (Geom.vertCCW(eCur.Lprev!.Org!, eCur.Org!, eSym.Lnext.Lnext.Org!) &&
                            Geom.vertCCW(eSym.Lprev!.Org!, eSym.Org!, eCur.Lnext.Lnext.Org!)) {
                            eNext = eSym.Lnext
                            delete(eSym)
                            eCur = nil
                        }
                    }
                }
                
                if (eCur != nil && eCur.Lnext.Org == vStart) {
                    break
                }
            }
        }
    }
    
    func check() {
        // Loops backwards across edges, faces and vertices of this mesh, make
        // sure everything is tidy and correctly set.
        var e: Edge
        
        var fPrev = _fHead
        var f = _fHead
        
        while fPrev.next != _fHead
        {
            defer {
                fPrev = f
            }
            
            f = fPrev.next
            
            e = f.anEdge
            repeat {
                assert(e.Sym != e)
                assert(e.Sym.Sym == e)
                assert(e.Lnext.Onext.Sym == e)
                assert(e.Onext.Sym.Lnext == e)
                assert(e.Lface == f)
                e = e.Lnext
            } while (e != f.anEdge)
        }
        
        f = fPrev.next
        
        assert(f.prev == fPrev && f.anEdge == nil)
        
        var vPrev = _vHead
        var v = _vHead
        
        while vPrev.next != _vHead
        {
            defer {
                vPrev = v
            }
            
            v = vPrev.next
            
            assert(v.prev == vPrev)
            e = v.anEdge
            repeat {
                assert(e.Sym != e)
                assert(e.Sym.Sym == e)
                assert(e.Lnext.Onext.Sym == e)
                assert(e.Onext.Sym.Lnext == e)
                assert(e.Org == v)
                e = e.Onext
            } while (e != v.anEdge)
        }
        
        v = vPrev.next
        
        assert(v.prev == vPrev && v.anEdge == nil)
        
        var ePrev = _eHead
        e = _eHead
        
        while ePrev.next != _eHead
        {
            defer {
                ePrev = e
            }
            
            e = ePrev.next
            
            assert(e.Sym.next == ePrev.Sym)
            assert(e.Sym != e)
            assert(e.Sym.Sym == e)
            assert(e.Org != nil)
            assert(e.Dst != nil)
            assert(e.Lnext.Onext.Sym == e)
            assert(e.Onext.Sym.Lnext == e)
        }
        
        e = ePrev.next
        
        assert(e.Sym.next == ePrev.Sym)
        assert(e.Sym == _eHeadSym)
        assert(e.Sym.Sym == e)
        assert(e.Org == nil)
        assert(e.Dst == nil)
        assert(e.Lface == nil)
        assert(e.Rface == nil)
    }
}
