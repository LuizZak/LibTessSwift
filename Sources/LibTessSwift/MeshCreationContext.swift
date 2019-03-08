//
//  MeshCreationContext.swift
//  Pods
//
//  Created by Luiz Fernando Silva on 28/02/17.
//
//

/// Caches and manages information that is used during mesh generation
internal final class MeshCreationContext {
    
    private var _poolFaces = Pool<MeshUtils._Face>()
    private var _poolEdges = Pool<MeshUtils._Edge>()
    private var _poolVerts = Pool<MeshUtils._Vertex>()
    
    deinit {
        free()
    }
    
    func free() {
        _poolFaces.free()
        _poolEdges.free()
        _poolVerts.free()
    }
    
    func reset() {
        _poolFaces.reset()
        _poolEdges.reset()
        _poolVerts.reset()
    }
    
    func createFace() -> Face {
        return _poolFaces.pull()
    }
    func resetFace(_ face: Face) {
        _poolFaces.repool(face)
    }
    
    func createEdgePair() -> (pair: MeshUtils.EdgePair, e: Edge, eSym: Edge) {
        let e = createEdge()
        let eSym = createEdge()
        
        var pair = MeshUtils.EdgePair()
        pair._e = e
        pair._e?.pair = pair
        pair._eSym = eSym
        pair._eSym?.pair = pair
        
        return (pair, e, eSym)
    }
    
    func createEdge() -> Edge {
        return _poolEdges.pull()
    }
    func resetEdge(_ edge: Edge) {
        _poolEdges.repool(edge)
    }
    
    func createVertex() -> Vertex {
        return _poolVerts.pull()
    }
    func resetVertex(_ vertex: Vertex) {
        _poolVerts.repool(vertex)
    }
    
    /// <summary>
    /// MakeEdge creates a new pair of half-edges which form their own loop.
    /// No vertex or face structures are allocated, but these must be assigned
    /// before the current edge operation is completed.
    /// </summary>
    func makeEdge(_ eNext: Edge) -> Edge {
        var eNext = eNext
        
        let (_, e, eSym) = createEdgePair()
        
        // Make sure eNext points to the first edge of the edge pair
        MeshUtils._Edge.ensureFirst(e: &eNext)
        
        // Insert in circular doubly-linked list before eNext.
        // Note that the prev pointer is stored in Sym->next.
        let ePrev = eNext.sym.next
        eSym.next = ePrev
        ePrev?.sym.next = e
        e.next = eNext
        eNext.sym.next = eSym
        
        e.sym = eSym
        e.Onext = e
        e.Lnext = eSym
        e.Org = nil
        e.Lface = nil
        e.winding = 0
        e.activeRegion = nil
        
        eSym.sym = e
        eSym.Onext = eSym
        eSym.Lnext = e
        eSym.Org = nil
        eSym.Lface = nil
        eSym.winding = 0
        eSym.activeRegion = nil
        
        return e
    }
    
    /// <summary>
    /// makeVertex( eOrig, vNext ) attaches a new vertex and makes it the
    /// origin of all edges in the vertex loop to which eOrig belongs. "vNext"
    /// gives a place to insert the new vertex in the global vertex list. We
    /// insert the new vertex *before* vNext so that algorithms which walk the
    /// vertex list will not see the newly created vertices.
    /// </summary>
    func makeVertex(_ eOrig: Edge, _ vNext: Vertex) {
        let vNew = createVertex()
        
        // insert in circular doubly-linked list before vNext
        let vPrev = vNext.prev
        vNew.prev = vPrev
        vPrev?.next = vNew
        vNew.next = vNext
        vNext.prev = vNew
        
        vNew.anEdge = eOrig
        // leave coords, s, t undefined
        
        // fix other edges on this vertex loop
        var e: Edge? = eOrig
        repeat {
            e?.Org = vNew
            e = e?.Onext
        } while (e != eOrig)
    }
    
    /// <summary>
    /// makeFace( eOrig, fNext ) attaches a new face and makes it the left face
    /// of all edges in the face loop to which eOrig belongs. "fNext" gives a
    /// place to insert the new face in the global face list. We insert the new
    /// face *before* fNext so that algorithms which walk the face list will not
    /// see the newly created faces.
    /// </summary>
    func makeFace(_ eOrig: Edge, _ fNext: Face) {
        let fNew = createFace()
        
        // insert in circular doubly-linked list before fNext
        let fPrev = fNext.prev
        fNew.prev = fPrev
        fPrev?.next = fNew
        fNew.next = fNext
        fNext.prev = fNew
        
        fNew.anEdge = eOrig
        fNew.marked = false
        
        // The new face is marked "inside" if the old one was. This is a
        // convenience for the common case where a face has been split in two.
        fNew.inside = fNext.inside
        
        // fix other edges on this face loop
        
        var edp = eOrig
        repeat {
            edp.Lface = fNew
            edp = edp.Lnext.unsafelyUnwrapped
        } while edp != eOrig
    }
    
    /// <summary>
    /// killEdge( eDel ) destroys an edge (the half-edges eDel and eDel->Sym),
    /// and removes from the global edge list.
    /// </summary>
    func killEdge(_ eDel: Edge) {
        // Half-edges are allocated in pairs, see EdgePair above
        var eDel = eDel
        MeshUtils._Edge.ensureFirst(e: &eDel)
        
        // delete from circular doubly-linked list
        let eNext = eDel.next
        let ePrev = eDel.sym.next
        eNext?.sym.next = ePrev
        ePrev?.sym.next = eNext
        
        eDel.pair = nil
        
        resetEdge(eDel)
    }
    
    /// <summary>
    /// killVertex( vDel ) destroys a vertex and removes it from the global
    /// vertex list. It updates the vertex loop to point to a given new vertex.
    /// </summary>
    func killVertex(_ vDel: Vertex, _ newOrg: Vertex?) {
        let eStart = vDel.anEdge
        
        // change the origin of all affected edges
        var e: Edge? = eStart
        repeat {
            e?.Org = newOrg
            e = e?.Onext
        } while (e != eStart)
        
        // delete from circular doubly-linked list
        let vPrev = vDel.prev
        let vNext = vDel.next
        vNext?.prev = vPrev
        vPrev?.next = vNext
        
        resetVertex(vDel)
    }
    
    /// <summary>
    /// killFace( fDel ) destroys a face and removes it from the global face
    /// list. It updates the face loop to point to a given new face.
    /// </summary>
    func killFace(_ fDel: Face, _ newLFace: Face?) {
        let eStart = fDel.anEdge!
        
        // change the left face of all affected edges
        var e: Edge = eStart
        repeat {
            e.pointee._Lface = newLFace
            e = e.pointee._Lnext.unsafelyUnwrapped
        } while e != eStart
        
        // delete from circular doubly-linked list
        let fPrev = fDel.prev
        let fNext = fDel.next
        fNext?.prev = fPrev
        fPrev?.next = fNext
        
        resetFace(fDel)
    }
}
