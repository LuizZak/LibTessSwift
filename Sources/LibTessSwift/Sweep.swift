//
//  Sweep.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

typealias ActiveRegion = UnsafeMutablePointer<Tess._ActiveRegion>

extension UnsafeMutablePointer where Pointee == Tess._ActiveRegion {
    var eUp: Edge! { get { return pointee._eUp } nonmutating set { pointee._eUp = newValue } }
    var nodeUp: Node<ActiveRegion>! { get { return pointee._nodeUp } nonmutating set { pointee._nodeUp = newValue } }
    var windingNumber: Int { get { return pointee._windingNumber } nonmutating set { pointee._windingNumber = newValue } }
    var inside: Bool { get { return pointee._inside } nonmutating set { pointee._inside = newValue } }
    var sentinel: Bool { get { return pointee._sentinel } nonmutating set { pointee._sentinel = newValue } }
    var dirty: Bool { get { return pointee._dirty } nonmutating set { pointee._dirty = newValue } }
    var fixUpperEdge: Bool { get { return pointee._fixUpperEdge } nonmutating set { pointee._fixUpperEdge = newValue } }
}

extension Tess {
    
    internal struct _ActiveRegion: EmptyInitializable {
        internal var _eUp: Edge!
        internal var _nodeUp: Node<ActiveRegion>!
        internal var _windingNumber: Int = 0
        internal var _inside: Bool = false, _sentinel: Bool = false, _dirty: Bool = false, _fixUpperEdge: Bool = false
    }

    private func regionBelow(_ reg: ActiveRegion) -> ActiveRegion! {
        return reg.nodeUp.pointee.Prev?.pointee.Key
    }

    private func regionAbove(_ reg: ActiveRegion) -> ActiveRegion! {
        return reg.nodeUp.pointee.Next?.pointee.Key
    }
    
    
    /// <summary>
    /// Both edges must be directed from right to left (this is the canonical
    /// direction for the upper edge of each region).
    /// 
    /// The strategy is to evaluate a "t" value for each edge at the
    /// current sweep line position, given by tess->event. The calculations
    /// are designed to be very stable, but of course they are not perfect.
    /// 
    /// Special case: if both edge destinations are at the sweep event,
    /// we sort the edges by slope (they would otherwise compare equally).
    /// </summary>
    private func edgeLeq(_ reg1: ActiveRegion, _ reg2: ActiveRegion) -> Bool {
        let e1 = reg1.eUp!
        let e2 = reg2.eUp!
        
        let e1_Dst = e1.Dst!
        let e1_Org = e1.Org!
        let e2_Dst = e2.Dst!
        let e2_Org = e2.Org!
        
        let event = _event!
        
        if e1_Dst == event {
            if e2_Dst == event {
                // Two edges right of the sweep line which meet at the sweep event.
                // Sort them by slope.
                if Geom.vertLeq(e1_Org, e2_Org) {
                    return Geom.edgeSign(e2_Dst, e1_Org, e2_Org) <= 0.0
                }
                return Geom.edgeSign(e1_Dst, e2_Org, e1_Org) >= 0.0
            }
            return Geom.edgeSign(e2_Dst, event, e2_Org) <= 0.0
        }
        if (e2_Dst == event) {
            return Geom.edgeSign(e1_Dst, event, e1_Org) >= 0.0
        }

        // General case - compute signed distance *from* e1, e2 to event
        let t1 = Geom.edgeEval(e1_Dst, event, e1_Org)
        let t2 = Geom.edgeEval(e2_Dst, event, e2_Org)
        return (t1 >= t2)
    }

    
    private func deleteRegion(_ reg: ActiveRegion) {
        if (reg.fixUpperEdge) {
            // It was created with zero winding number, so it better be
            // deleted with zero winding number (ie. it better not get merged
            // with a real edge).
            assert(reg.eUp.winding == 0)
        }
        reg.eUp.activeRegion = nil
        _dict.remove(node: reg.nodeUp)
        
        reg.eUp = nil
        reg.windingNumber = 0
        reg.nodeUp = nil
        
        _regionsPool.repool(reg)
    }

    /// <summary>
    /// Replace an upper edge which needs fixing (see connectRightVertex).
    /// </summary>
    private func fixUpperEdge(_ reg: ActiveRegion, _ newEdge: Edge) {
        assert(reg.fixUpperEdge)
        mesh.delete(reg.eUp)
        reg.fixUpperEdge = false
        reg.eUp = newEdge
        newEdge.activeRegion = reg
    }

    private func topLeftRegion(_ reg: ActiveRegion) -> ActiveRegion! {
        var reg = reg
        let org = reg.eUp.Org

        // Find the region above the uppermost edge with the same origin
        repeat {
            reg = regionAbove(reg)!
        } while (reg.eUp.Org == org)

        // If the edge above was a temporary edge introduced by connectRightVertex,
        // now is the time to fix it.
        if (reg.fixUpperEdge) {
            let e = mesh.connect(regionBelow(reg).eUp.Sym, reg.eUp.Lnext)
            fixUpperEdge(reg, e)
            reg = regionAbove(reg)!
        }

        return reg
    }
    
    private func topRightRegion(_ reg: ActiveRegion) -> ActiveRegion! {
        var reg = reg
        let dst = reg.eUp.Dst

        // Find the region above the uppermost edge with the same destination
        repeat {
            reg = regionAbove(reg)!
        } while (reg.eUp.Dst == dst)

        return reg
    }

    /// <summary>
    /// Add a new active region to the sweep line, *somewhere* below "regAbove"
    /// (according to where the new edge belongs in the sweep-line dictionary).
    /// The upper edge of the new region will be "eNewUp".
    /// Winding number and "inside" flag are not updated.
    /// </summary>
    private func addRegionBelow(_ regAbove: ActiveRegion, _ eNewUp: Edge) -> ActiveRegion {
        let regNew = _regionsPool.pull()

        regNew.eUp = eNewUp
        regNew.nodeUp = _dict.insertBefore(node: regAbove.nodeUp, key: regNew)
        regNew.fixUpperEdge = false
        regNew.sentinel = false
        regNew.dirty = false

        eNewUp.activeRegion = regNew

        return regNew
    }

    private func computeWinding(_ reg: ActiveRegion) {
        reg.windingNumber = regionAbove(reg).windingNumber + reg.eUp.winding
        reg.inside = Geom.isWindingInside(windingRule, reg.windingNumber)
    }
    
    /// <summary>
    /// Delete a region from the sweep line. This happens when the upper
    /// and lower chains of a region meet (at a vertex on the sweep line).
    /// The "inside" flag is copied to the appropriate mesh face (we could
    /// not do this before -- since the structure of the mesh is always
    /// changing, this face may not have even existed until now).
    /// </summary>
    private func finishRegion(_ reg: ActiveRegion) {
        let e = reg.eUp
        let f: Face! = e!.Lface

        f.inside = reg.inside
        f.anEdge = e
        
        deleteRegion(reg)
    }

    /// <summary>
    /// We are given a vertex with one or more left-going edges.  All affected
    /// edges should be in the edge dictionary.  Starting at regFirst->eUp,
    /// we walk down deleting all regions where both edges have the same
    /// origin vOrg.  At the same time we copy the "inside" flag from the
    /// active region to the face, since at this point each face will belong
    /// to at most one region (this was not necessarily true until this point
    /// in the sweep).  The walk stops at the region above regLast; if regLast
    /// is nil we walk as far as possible.  At the same time we relink the
    /// mesh if necessary, so that the ordering of edges around vOrg is the
    /// same as in the dictionary.
    /// </summary>
    @discardableResult
    private func finishLeftRegions(_ regFirst: ActiveRegion, _ regLast: ActiveRegion?) -> Edge {
        var regPrev = regFirst
        var ePrev = regFirst.eUp!
        
        while (regPrev != regLast) {
            regPrev.fixUpperEdge = false	// placement was OK
            let reg = regionBelow(regPrev)!
            var e = reg.eUp!
            if (e.Org != ePrev.Org) {
                if (!reg.fixUpperEdge) {
                    // Remove the last left-going edge.  Even though there are no further
                    // edges in the dictionary with this origin, there may be further
                    // such edges in the mesh (if we are adding left edges to a vertex
                    // that has already been processed).  Thus it is important to call
                    // FinishRegion rather than just deleteRegion.
                    finishRegion(regPrev)
                    break
                }
                // If the edge below was a temporary edge introduced by
                // connectRightVertex, now is the time to fix it.
                e = mesh.connect(ePrev.Lprev, e.Sym)
                fixUpperEdge(reg, e)
            }

            // Relink edges so that ePrev.Onext == e
            if (ePrev.Onext != e) {
                mesh.splice(e.Oprev, e)
                mesh.splice(ePrev, e)
            }
            finishRegion(regPrev) // may change reg.eUp
            ePrev = reg.eUp
            regPrev = reg
        }

        return ePrev
    }

    /// <summary>
    /// Purpose: insert right-going edges into the edge dictionary, and update
    /// winding numbers and mesh connectivity appropriately.  All right-going
    /// edges share a common origin vOrg.  Edges are inserted CCW starting at
    /// eFirst; the last edge inserted is eLast.Oprev.  If vOrg has any
    /// left-going edges already processed, then eTopLeft must be the edge
    /// such that an imaginary upward vertical segment from vOrg would be
    /// contained between eTopLeft.Oprev and eTopLeft; otherwise eTopLeft
    /// should be nil.
    /// </summary>
    private func addRightEdges(_ regUp: ActiveRegion, _ eFirst: Edge, _ eLast: Edge, _ eTopLeft: Edge?, cleanUp: Bool) {
        var eTopLeft = eTopLeft
        var firstTime = true

        var e = eFirst
        
        repeat {
            assert(Geom.vertLeq(e.Org, e.Dst))
            _=addRegionBelow(regUp, e.Sym)
            e = e.Onext
        } while (e != eLast)
        
        // Walk *all* right-going edges from e.Org, in the dictionary order,
        // updating the winding numbers of each region, and re-linking the mesh
        // edges to match the dictionary ordering (if necessary).
        if (eTopLeft == nil) {
            eTopLeft = regionBelow(regUp)?.eUp.Rprev
        }

        var regPrev = regUp
        var reg = regionBelow(regPrev)
        var ePrev = eTopLeft!
        while (true) {
            reg = regionBelow(regPrev)
            e = reg!.eUp.Sym
            if (e.Org != ePrev.Org) { break }
            
            if (e.Onext != ePrev) {
                // Unlink e from its current position, and relink below ePrev
                mesh.splice(e.Oprev, e)
                mesh.splice(ePrev.Oprev, e)
            }
            // Compute the winding number and "inside" flag for the new regions
            reg!.windingNumber = regPrev.windingNumber - e.winding
            reg!.inside = Geom.isWindingInside(windingRule, reg!.windingNumber)
            
            // Check for two outgoing edges with same slope -- process these
            // before any intersection tests (see example in tessComputeInterior).
            regPrev.dirty = true
            if (!firstTime && checkForRightSplice(regPrev)) {
                Geom.addWinding(e, ePrev)
                deleteRegion(regPrev)
                mesh.delete(ePrev)
            }
            firstTime = false
            regPrev = reg!
            ePrev = e
        }
        regPrev.dirty = true
        assert(regPrev.windingNumber - e.winding == reg!.windingNumber)
        
        if (cleanUp) {
            // Check for intersections between newly adjacent edges.
            walkDirtyRegions(regPrev)
        }
    }
    
    /// <summary>
    /// Two vertices with idential coordinates are combined into one.
    /// e1.Org is kept, while e2.Org is discarded.
    /// </summary>
    private func spliceMergeVertices(_ e1: Edge, _ e2: Edge) {
        mesh.splice(e1, e2)
    }

    /// <summary>
    /// Find some weights which describe how the intersection vertex is
    /// a linear combination of "org" and "dest".  Each of the two edges
    /// which generated "isect" is allocated 50% of the weight; each edge
    /// splits the weight between its org and dst according to the
    /// relative distance to "isect".
    /// </summary>
    private func vertexWeights(_ isect: Vertex, _ org: Vertex, _ dst: Vertex, _ w0: inout Real, _ w1: inout Real) {
        let t1 = Geom.VertL1dist(u: org, v: isect)
        let t2 = Geom.VertL1dist(u: dst, v: isect)

        w0 = (t2 / (t1 + t2)) / 2.0
        w1 = (t1 / (t1 + t2)) / 2.0

        isect.coords.x += w0 * org.coords.x + w1 * dst.coords.x
        isect.coords.y += w0 * org.coords.y + w1 * dst.coords.y
        isect.coords.z += w0 * org.coords.z + w1 * dst.coords.z
    }

    /// <summary>
    /// We've computed a new intersection point, now we need a "data" pointer
    /// from the user so that we can refer to this new vertex in the
    /// rendering callbacks.
    /// </summary>
    private func getIntersectData(_ isect: Vertex, _ orgUp: Vertex, _ dstUp: Vertex, _ orgLo: Vertex, _ dstLo: Vertex) {
        isect.coords = Vector3.zero
        
        var w0: Real = 0, w1: Real = 0, w2: Real = 0, w3: Real = 0
        
        vertexWeights(isect, orgUp, dstUp, &w0, &w1)
        vertexWeights(isect, orgLo, dstLo, &w2, &w3)

        if let callback = _combineCallback {
            isect.data = callback(
                isect.coords,
                [ orgUp.data, dstUp.data, orgLo.data, dstLo.data ],
                [ w0, w1, w2, w3 ]
            )
        }
    }

    /// <summary>
    /// Check the upper and lower edge of "regUp", to make sure that the
    /// eUp->Org is above eLo, or eLo->Org is below eUp (depending on which
    /// origin is leftmost).
    /// 
    /// The main purpose is to splice right-going edges with the same
    /// dest vertex and nearly identical slopes (ie. we can't distinguish
    /// the slopes numerically).  However the splicing can also help us
    /// to recover from numerical errors.  For example, suppose at one
    /// point we checked eUp and eLo, and decided that eUp->Org is barely
    /// above eLo.  Then later, we split eLo into two edges (eg. from
    /// a splice operation like this one).  This can change the result of
    /// our test so that now eUp->Org is incident to eLo, or barely below it.
    /// We must correct this condition to maintain the dictionary invariants.
    /// 
    /// One possibility is to check these edges for intersection again
    /// (ie. checkForIntersect).  This is what we do if possible.  However
    /// CheckForIntersect requires that tess->event lies between eUp and eLo,
    /// so that it has something to fall back on when the intersection
    /// calculation gives us an unusable answer.  So, for those cases where
    /// we can't check for intersection, this routine fixes the problem
    /// by just splicing the offending vertex into the other edge.
    /// This is a guaranteed solution, no matter how degenerate things get.
    /// Basically this is a combinatorial solution to a numerical problem.
    /// </summary>
    @discardableResult
    private func checkForRightSplice(_ regUp: ActiveRegion) -> Bool {
        let regLo = regionBelow(regUp)!
        let eUp = regUp.eUp!
        let eLo = regLo.eUp!

        if (Geom.vertLeq(eUp.Org, eLo.Org)) {
            if (Geom.edgeSign(eLo.Dst, eUp.Org, eLo.Org) > 0.0) {
                return false
            }

            // eUp.Org appears to be below eLo
            if (!Geom.vertEq(eUp.Org, eLo.Org)) {
                // Splice eUp._Org into eLo
                mesh.splitEdge(eLo.Sym)
                mesh.splice(eUp, eLo.Oprev)
                regUp.dirty = true
                regLo.dirty = true
            } else if (eUp.Org != eLo.Org) {
                // merge the two vertices, discarding eUp.Org
                _pq.remove(eUp.Org.pqHandle)
                spliceMergeVertices(eLo.Oprev, eUp)
            }
        } else {
            if (Geom.edgeSign(eUp.Dst, eLo.Org, eUp.Org) < 0.0) {
                return false
            }

            // eLo.Org appears to be above eUp, so splice eLo.Org into eUp
            regionAbove(regUp).dirty = true
            regUp.dirty = true
            mesh.splitEdge(eUp.Sym)
            mesh.splice(eLo.Oprev, eUp)
        }
        return true
    }
    
    /// <summary>
    /// Check the upper and lower edge of "regUp", to make sure that the
    /// eUp->Dst is above eLo, or eLo->Dst is below eUp (depending on which
    /// destination is rightmost).
    /// 
    /// Theoretically, this should always be true.  However, splitting an edge
    /// into two pieces can change the results of previous tests.  For example,
    /// suppose at one point we checked eUp and eLo, and decided that eUp->Dst
    /// is barely above eLo.  Then later, we split eLo into two edges (eg. from
    /// a splice operation like this one).  This can change the result of
    /// the test so that now eUp->Dst is incident to eLo, or barely below it.
    /// We must correct this condition to maintain the dictionary invariants
    /// (otherwise new edges might get inserted in the wrong place in the
    /// dictionary, and bad stuff will happen).
    /// 
    /// We fix the problem by just splicing the offending vertex into the
    /// other edge.
    /// </summary>
    private func checkForLeftSplice(_ regUp: ActiveRegion) -> Bool {
        let regLo = regionBelow(regUp)!
        let eUp = regUp.eUp!
        let eLo = regLo.eUp!

        assert(!Geom.vertEq(eUp.Dst, eLo.Dst))

        if (Geom.vertLeq(eUp.Dst, eLo.Dst)) {
            if (Geom.edgeSign(eUp.Dst, eLo.Dst, eUp.Org) < 0.0) {
                return false
            }

            // eLo.Dst is above eUp, so splice eLo.Dst into eUp
            regionAbove(regUp).dirty = true
            regUp.dirty = true
            let e = mesh.splitEdge(eUp)
            mesh.splice(eLo.Sym, e)
            e.Lface.inside = regUp.inside
        } else {
            if (Geom.edgeSign(eLo.Dst, eUp.Dst, eLo.Org) > 0.0) {
                return false
            }

            // eUp.Dst is below eLo, so splice eUp.Dst into eLo
            regUp.dirty = true
            regLo.dirty = true
            let e = mesh.splitEdge(eLo)
            mesh.splice(eUp.Lnext, eLo.Sym)
            e.Rface.inside = regUp.inside
        }
        return true
    }

    /// <summary>
    /// Check the upper and lower edges of the given region to see if
    /// they intersect.  If so, create the intersection and add it
    /// to the data structures.
    /// 
    /// Returns TRUE if adding the new intersection resulted in a recursive
    /// call to addRightEdges(); in this case all "dirty" regions have been
    /// checked for intersections, and possibly regUp has been deleted.
    /// </summary>
    @discardableResult
    private func checkForIntersect(_ regUp: ActiveRegion) -> Bool {
        var regUp = regUp
        var regLo = regionBelow(regUp)!
        var eUp = regUp.eUp!
        var eLo = regLo.eUp!
        let orgUp = eUp.Org!
        let orgLo = eLo.Org!
        let dstUp = eUp.Dst!
        let dstLo = eLo.Dst!

        assert(!Geom.vertEq(dstLo, dstUp))
        assert(Geom.edgeSign(dstUp, _event, orgUp) <= 0.0)
        assert(Geom.edgeSign(dstLo, _event, orgLo) >= 0.0)
        assert(orgUp != _event && orgLo != _event)
        assert(!regUp.fixUpperEdge && !regLo.fixUpperEdge)

        if( orgUp == orgLo ) {
            // right endpoints are the same
            return false
        }

        let tMinUp = min(orgUp.t, dstUp.t)
        let tMaxLo = max(orgLo.t, dstLo.t)
        if( tMinUp > tMaxLo ) {
            // t ranges do not overlap
            return false
        }

        if (Geom.vertLeq(orgUp, orgLo)) {
            if (Geom.edgeSign( dstLo, orgUp, orgLo ) > 0.0) {
                return false
            }
        } else {
            if (Geom.edgeSign( dstUp, orgLo, orgUp ) < 0.0) {
                return false
            }
        }

        // At this point the edges intersect, at least marginally
        let isect = mesh._context.createVertex()
        Geom.edgeIntersect(o1: dstUp, d1: orgUp, o2: dstLo, d2: orgLo, v: isect)
        // The following properties are guaranteed:
        assert(min(orgUp.t, dstUp.t) <= isect.t)
        assert(isect.t <= max(orgLo.t, dstLo.t))
        assert(min(dstLo.s, dstUp.s) <= isect.s)
        assert(isect.s <= max(orgLo.s, orgUp.s))

        if (Geom.vertLeq(isect, _event)) {
            // The intersection point lies slightly to the left of the sweep line,
            // so move it until it''s slightly to the right of the sweep line.
            // (If we had perfect numerical precision, this would never happen
            // in the first place). The easiest and safest thing to do is
            // replace the intersection by tess._event.
            isect.s = _event.s
            isect.t = _event.t
        }
        // Similarly, if the computed intersection lies to the right of the
        // rightmost origin (which should rarely happen), it can cause
        // unbelievable inefficiency on sufficiently degenerate inputs.
        // (If you have the test program, try running test54.d with the
        // "X zoom" option turned on).
        let orgMin = Geom.vertLeq(orgUp, orgLo) ? orgUp : orgLo
        if (Geom.vertLeq(orgMin, isect)) {
            isect.s = orgMin.s
            isect.t = orgMin.t
        }

        if (Geom.vertEq(isect, orgUp) || Geom.vertEq(isect, orgLo)) {
            // Easy case -- intersection at one of the right endpoints
            checkForRightSplice(regUp)
            return false
        }

        if (   (!Geom.vertEq(dstUp, _event)
            && Geom.edgeSign(dstUp, _event, isect) >= 0.0)
            || (!Geom.vertEq(dstLo, _event)
            && Geom.edgeSign(dstLo, _event, isect) <= 0.0)) {
            // Very unusual -- the new upper or lower edge would pass on the
            // wrong side of the sweep event, or through it. This can happen
            // due to very small numerical errors in the intersection calculation.
            if (dstLo == _event) {
                // Splice dstLo into eUp, and process the new region(s)
                mesh.splitEdge(eUp.Sym)
                mesh.splice(eLo.Sym, eUp)
                regUp = topLeftRegion(regUp)
                eUp = regionBelow(regUp).eUp
                finishLeftRegions(regionBelow(regUp), regLo)
                addRightEdges(regUp, eUp.Oprev, eUp, eUp, cleanUp: true)
                return true
            }
            if( dstUp == _event ) {
                /* Splice dstUp into eLo, and process the new region(s) */
                mesh.splitEdge(eLo.Sym)
                mesh.splice(eUp.Lnext, eLo.Oprev)
                regLo = regUp
                regUp = topRightRegion(regUp)
                let e = regionBelow(regUp).eUp.Rprev
                regLo.eUp = eLo.Oprev
                eLo = finishLeftRegions(regLo, nil)
                addRightEdges(regUp, eLo.Onext, eUp.Rprev, e, cleanUp: true)
                return true
            }
            // Special case: called from connectRightVertex. If either
            // edge passes on the wrong side of tess._event, split it
            // (and wait for connectRightVertex to splice it appropriately).
            if (Geom.edgeSign( dstUp, _event, isect ) >= 0.0) {
                regionAbove(regUp).dirty = true
                regUp.dirty = true
                mesh.splitEdge(eUp.Sym)
                eUp.Org.s = _event.s
                eUp.Org.t = _event.t
            }
            if (Geom.edgeSign(dstLo, _event, isect) <= 0.0) {
                regUp.dirty = true
                regLo.dirty = true
                mesh.splitEdge(eLo.Sym)
                eLo.Org.s = _event.s
                eLo.Org.t = _event.t
            }
            // leave the rest for connectRightVertex
            return false
        }

        // General case -- split both edges, splice into new vertex.
        // When we do the splice operation, the order of the arguments is
        // arbitrary as far as correctness goes. However, when the operation
        // creates a new face, the work done is proportional to the size of
        // the new face.  We expect the faces in the processed part of
        // the mesh (ie. eUp._Lface) to be smaller than the faces in the
        // unprocessed original contours (which will be eLo._Oprev._Lface).
        mesh.splitEdge(eUp.Sym)
        mesh.splitEdge(eLo.Sym)
        mesh.splice(eLo.Oprev, eUp)
        eUp.Org.s = isect.s
        eUp.Org.t = isect.t
        eUp.Org.pqHandle = _pq.insert(eUp.Org)
        if (eUp.Org.pqHandle._handle == PQHandle.Invalid) {
            // TODO: Use a proper throw here
            fatalError("PQHandle should not be invalid")
            //throw new InvalidOperationException("PQHandle should not be invalid")
        }
        getIntersectData(eUp.Org, orgUp, dstUp, orgLo, dstLo)
        regionAbove(regUp).dirty = true
        regUp.dirty = true
        regLo.dirty = true
        return false
    }

    /// <summary>
    /// When the upper or lower edge of any region changes, the region is
    /// marked "dirty".  This routine walks through all the dirty regions
    /// and makes sure that the dictionary invariants are satisfied
    /// (see the comments at the beginning of this file).  Of course
    /// new dirty regions can be created as we make changes to restore
    /// the invariants.
    /// </summary>
    private func walkDirtyRegions(_ regUp: ActiveRegion) {
        
        var regUp: ActiveRegion! = regUp
        var regLo = regionBelow(regUp)!
        var eUp: Edge, eLo: Edge

        while (true) {
            // Find the lowest dirty region (we walk from the bottom up).
            while (regLo.dirty) {
                regUp = regLo
                regLo = regionBelow(regLo)
            }
            if (!regUp.dirty) {
                regLo = regUp
                regUp = regionAbove( regUp )
                if(regUp == nil || !regUp.dirty) {
                    // We've walked all the dirty regions
                    return
                }
            }
            regUp.dirty = false
            eUp = regUp.eUp
            eLo = regLo.eUp
            
            if (eUp.Dst != eLo.Dst) {
                // Check that the edge ordering is obeyed at the Dst vertices.
                if (checkForLeftSplice(regUp)) {

                    // If the upper or lower edge was marked fixUpperEdge, then
                    // we no longer need it (since these edges are needed only for
                    // vertices which otherwise have no right-going edges).
                    if (regLo.fixUpperEdge) {
                        deleteRegion(regLo)
                        mesh.delete(eLo)
                        regLo = regionBelow(regUp)
                        eLo = regLo.eUp
                    } else if( regUp.fixUpperEdge ) {
                        deleteRegion(regUp)
                        mesh.delete(eUp)
                        regUp = regionAbove(regLo)
                        eUp = regUp.eUp
                    }
                }
            }
            
            if (eUp.Org != eLo.Org) {
                if(
                    eUp.Dst != eLo.Dst
                    && !regUp.fixUpperEdge && !regLo.fixUpperEdge
                    && (eUp.Dst == _event || eLo.Dst == _event)
                    ) {
                    // When all else fails in checkForIntersect(), it uses tess._event
                    // as the intersection location. To make this possible, it requires
                    // that tess._event lie between the upper and lower edges, and also
                    // that neither of these is marked fixUpperEdge (since in the worst
                    // case it might splice one of these edges into tess.event, and
                    // violate the invariant that fixable edges are the only right-going
                    // edge from their associated vertex).
                    if (checkForIntersect(regUp)) {
                        // walkDirtyRegions() was called recursively; we're done
                        return
                    }
                } else {
                    // Even though we can't use checkForIntersect(), the Org vertices
                    // may violate the dictionary edge ordering. Check and correct this.
                    checkForRightSplice(regUp)
                }
            }
            if (eUp.Org == eLo.Org && eUp.Dst == eLo.Dst) {
                // A degenerate loop consisting of only two edges -- delete it.
                Geom.addWinding(eLo, eUp)
                deleteRegion(regUp)
                mesh.delete(eUp)
                regUp = regionAbove(regLo)
            }
        }
    }
    
    /// <summary>
    /// Purpose: connect a "right" vertex vEvent (one where all edges go left)
    /// to the unprocessed portion of the mesh.  Since there are no right-going
    /// edges, two regions (one above vEvent and one below) are being merged
    /// into one.  "regUp" is the upper of these two regions.
    /// 
    /// There are two reasons for doing this (adding a right-going edge):
    ///  - if the two regions being merged are "inside", we must add an edge
    ///    to keep them separated (the combined region would not be monotone).
    ///  - in any case, we must leave some record of vEvent in the dictionary,
    ///    so that we can merge vEvent with features that we have not seen yet.
    ///    For example, maybe there is a vertical edge which passes just to
    ///    the right of vEvent; we would like to splice vEvent into this edge.
    /// 
    /// However, we don't want to connect vEvent to just any vertex.  We don''t
    /// want the new edge to cross any other edges; otherwise we will create
    /// intersection vertices even when the input data had no self-intersections.
    /// (This is a bad thing; if the user's input data has no intersections,
    /// we don't want to generate any false intersections ourselves.)
    /// 
    /// Our eventual goal is to connect vEvent to the leftmost unprocessed
    /// vertex of the combined region (the union of regUp and regLo).
    /// But because of unseen vertices with all right-going edges, and also
    /// new vertices which may be created by edge intersections, we don''t
    /// know where that leftmost unprocessed vertex is.  In the meantime, we
    /// connect vEvent to the closest vertex of either chain, and mark the region
    /// as "fixUpperEdge".  This flag says to delete and reconnect this edge
    /// to the next processed vertex on the boundary of the combined region.
    /// Quite possibly the vertex we connected to will turn out to be the
    /// closest one, in which case we won''t need to make any changes.
    /// </summary>
    private func connectRightVertex(_ regUp: ActiveRegion, _ eBottomLeft: Edge) {
        var regUp = regUp
        var eBottomLeft = eBottomLeft
        var eTopLeft = eBottomLeft.Onext!
        let regLo = regionBelow(regUp)!
        let eUp = regUp.eUp!
        let eLo = regLo.eUp!
        var degenerate = false

        if (eUp.Dst != eLo.Dst) {
            checkForIntersect(regUp)
        }

        // Possible new degeneracies: upper or lower edge of regUp may pass
        // through vEvent, or may coincide with new intersection vertex
        if (Geom.vertEq(eUp.Org, _event)) {
            mesh.splice(eTopLeft.Oprev, eUp)
            regUp = topLeftRegion(regUp)!
            eTopLeft = regionBelow(regUp).eUp
            finishLeftRegions(regionBelow(regUp), regLo)
            degenerate = true
        }
        if (Geom.vertEq(eLo.Org, _event)) {
            mesh.splice(eBottomLeft, eLo.Oprev)
            eBottomLeft = finishLeftRegions(regLo, nil)
            degenerate = true
        }
        if (degenerate) {
            addRightEdges(regUp, eBottomLeft.Onext, eTopLeft, eTopLeft, cleanUp: true)
            return
        }

        // Non-degenerate situation -- need to add a temporary, fixable edge.
        // Connect to the closer of eLo.Org, eUp.Org.
        var eNew: Edge
        if (Geom.vertLeq(eLo.Org, eUp.Org)) {
            eNew = eLo.Oprev
        } else {
            eNew = eUp
        }
        eNew = mesh.connect(eBottomLeft.Lprev, eNew)

        // Prevent cleanup, otherwise eNew might disappear before we've even
        // had a chance to mark it as a temporary edge.
        addRightEdges(regUp, eNew, eNew.Onext, eNew.Onext, cleanUp: false)
        eNew.Sym.activeRegion.fixUpperEdge = true
        walkDirtyRegions(regUp)
    }

    /// <summary>
    /// The event vertex lies exacty on an already-processed edge or vertex.
    /// Adding the new vertex involves splicing it into the already-processed
    /// part of the mesh.
    /// </summary>
    private func connectLeftDegenerate(_ regUp: ActiveRegion, _ vEvent: Vertex) {
        let e = regUp.eUp!
        if (Geom.vertEq(e.Org, vEvent)) {
            // e.Org is an unprocessed vertex - just combine them, and wait
            // for e.Org to be pulled from the queue
            // C# : in the C version, there is a flag but it was never implemented
            // the vertices are before beginning the tesselation
            
            fatalError("Vertices should have been merged before")
            // TODO: Throw a proper error here
            //throw new InvalidOperationException("Vertices should have been merged before")
        }

        if (!Geom.vertEq(e.Dst, vEvent)) {
            // General case -- splice vEvent into edge e which passes through it
            mesh.splitEdge(e.Sym)
            if (regUp.fixUpperEdge) {
                // This edge was fixable -- delete unused portion of original edge
                mesh.delete(e.Onext)
                regUp.fixUpperEdge = false
            }
            mesh.splice(vEvent.anEdge, e)
            sweepEvent(vEvent)	// recurse
            return
        }

        // See above
        fatalError("Vertices should have been merged before")
        // TODO: Throw a proper error here
        //throw new InvalidOperationException("Vertices should have been merged before")
    }

    /// <summary>
    /// Purpose: connect a "left" vertex (one where both edges go right)
    /// to the processed portion of the mesh.  Let R be the active region
    /// containing vEvent, and let U and L be the upper and lower edge
    /// chains of R.  There are two possibilities:
    /// 
    /// - the normal case: split R into two regions, by connecting vEvent to
    ///   the rightmost vertex of U or L lying to the left of the sweep line
    /// 
    /// - the degenerate case: if vEvent is close enough to U or L, we
    ///   merge vEvent into that edge chain.  The subcases are:
    ///     - merging with the rightmost vertex of U or L
    ///     - merging with the active edge of U or L
    ///     - merging with an already-processed portion of U or L
    /// </summary>
    private func connectLeftVertex(_ vEvent: Vertex) {
        
        // Get a pointer to the active region containing vEvent
        let regUp = _regionsPool.withTemporary { tmp -> ActiveRegion in
            tmp.eUp = vEvent.anEdge.Sym
            
            return _dict.find(key: tmp).pointee.Key!
        }
        
        guard let regLo = regionBelow(regUp) else {
            // This may happen if the input polygon is coplanar.
            return
        }
        let eUp = regUp.eUp!
        let eLo = regLo.eUp!
        
        // Try merging with U or L first
        if (Geom.edgeSign(eUp.Dst, vEvent, eUp.Org) == 0.0) {
            connectLeftDegenerate(regUp, vEvent)
            return
        }
        
        // Connect vEvent to rightmost processed vertex of either chain.
        // e._Dst is the vertex that we will connect to vEvent.
        let reg = Geom.vertLeq(eLo.Dst, eUp.Dst) ? regUp : regLo

        if (regUp.inside || reg.fixUpperEdge) {
            var eNew: Edge
            if (reg == regUp) {
                eNew = mesh.connect(vEvent.anEdge.Sym, eUp.Lnext)
            } else {
                eNew = mesh.connect(eLo.Dnext, vEvent.anEdge).Sym
            }
            if (reg.fixUpperEdge) {
                fixUpperEdge(reg, eNew)
            } else {
                computeWinding(addRegionBelow(regUp, eNew))
            }
            sweepEvent(vEvent)
        } else {
            // The new vertex is in a region which does not belong to the polygon.
            // We don't need to connect this vertex to the rest of the mesh.
            addRightEdges(regUp, vEvent.anEdge, vEvent.anEdge, nil, cleanUp: true)
        }
    }

    /// <summary>
    /// Does everything necessary when the sweep line crosses a vertex.
    /// Updates the mesh and the edge dictionary.
    /// </summary>
    private func sweepEvent(_ vEvent: Vertex) {
        _event = vEvent

        // Check if this vertex is the right endpoint of an edge that is
        // already in the dictionary. In this case we don't need to waste
        // time searching for the location to insert new edges.
        var e = vEvent.anEdge!
        while (e.activeRegion == nil) {
            e = e.Onext
            if (e == vEvent.anEdge) {
                // All edges go right -- not incident to any processed edges
                connectLeftVertex(vEvent)
                return
            }
        }
        
        // Processing consists of two phases: first we "finish" all the
        // active regions where both the upper and lower edges terminate
        // at vEvent (ie. vEvent is closing off these regions).
        // We mark these faces "inside" or "outside" the polygon according
        // to their winding number, and delete the edges from the dictionary.
        // This takes care of all the left-going edges from vEvent.
        let regUp = topLeftRegion(e.activeRegion)!
        let reg = regionBelow(regUp)!
        let eTopLeft = reg.eUp!
        let eBottomLeft = finishLeftRegions(reg, nil)

        // Next we process all the right-going edges from vEvent. This
        // involves adding the edges to the dictionary, and creating the
        // associated "active regions" which record information about the
        // regions between adjacent dictionary edges.
        if (eBottomLeft.Onext == eTopLeft) {
            // No right-going edges -- add a temporary "fixable" edge
            connectRightVertex(regUp, eBottomLeft)
        } else {
            addRightEdges(regUp, eBottomLeft.Onext, eTopLeft, eTopLeft, cleanUp: true)
        }
    }

    /// <summary>
    /// Make the sentinel coordinates big enough that they will never be
    /// merged with real input features.
    /// 
    /// We add two sentinel edges above and below all other edges,
    /// to avoid special cases at the top and bottom.
    /// </summary>
    private func addSentinel(_ smin: Real, _ smax: Real, _ t: Real) {
        let e = mesh.makeEdge()
        e.Org.s = smax
        e.Org.t = t
        e.Dst.s = smin
        e.Dst.t = t
        _event = e.Dst // initialize it
        
        let reg = _regionsPool.pull()
        reg.eUp = e
        reg.windingNumber = 0
        reg.inside = false
        reg.fixUpperEdge = false
        reg.sentinel = true
        reg.dirty = false
        reg.nodeUp = _dict.insert(key: reg)
    }

    /// <summary>
    /// We maintain an ordering of edge intersections with the sweep line.
    /// This order is maintained in a dynamic dictionary.
    /// </summary>
    private func initEdgeDict() {
        _dict = Dict<ActiveRegion>(leq: edgeLeq)

        addSentinel(-SentinelCoord, SentinelCoord, -SentinelCoord)
        addSentinel(-SentinelCoord, SentinelCoord, +SentinelCoord)
    }

    private func doneEdgeDict() {
        var fixedEdges = 0

        while let reg = _dict.min()?.pointee.Key {
            // At the end of all processing, the dictionary should contain
            // only the two sentinel edges, plus at most one "fixable" edge
            // created by connectRightVertex().
            if (!reg.sentinel) {
                assert(reg.fixUpperEdge)
                fixedEdges += 1
                assert(fixedEdges == 1)
            }
            assert(reg.windingNumber == 0)
            deleteRegion(reg)
        }

        _dict = nil
    }

    /// <summary>
    /// Remove zero-length edges, and contours with fewer than 3 vertices.
    /// </summary>
    private func removeDegenerateEdges() {
        var eHead = mesh._eHead, eNext: Edge, eLnext: Edge
        
        // Can't use _mesh.forEachEdge due to a reassignment of the next edge
        // to step to
        var e = eHead.next!
        while e != eHead {
            defer {
                e = eNext
            }
            
            eNext = e.next
            eLnext = e.Lnext

            if (Geom.vertEq(e.Org, e.Dst) && e.Lnext.Lnext != e) {
                // Zero-length edge, contour has at least 3 edges

                spliceMergeVertices(eLnext, e)	// deletes e.Org
                mesh.delete(e) // e is a self-loop
                e = eLnext
                eLnext = e.Lnext // Can't use _mesh.forEachEdge due to this reassignment
            }
            if (eLnext.Lnext == e) {
                // Degenerate contour (one or two edges)

                if (eLnext != e) {
                    if (eLnext == eNext || eLnext == eNext.Sym) {
                        eNext = eNext.next
                    }
                    mesh.delete(eLnext)
                }
                if (e == eNext || e == eNext.Sym) {
                    eNext = eNext.next
                }
                mesh.delete(e)
            }
        }
    }

    /// <summary>
    /// Insert all vertices into the priority queue which determines the
    /// order in which vertices cross the sweep line.
    /// </summary>
    private func initPriorityQ() {
        var vertexCount = 0
        
        mesh.forEachVertex { v in
            vertexCount += 1
        }
        
        // Make sure there is enough space for sentinels.
        vertexCount += 8
        
        _pq = PriorityQueue<Vertex>(vertexCount, Geom.vertLeq)
        
        mesh.forEachVertex { v in
            v.pqHandle = _pq.insert(v)
            if (v.pqHandle._handle == PQHandle.Invalid) {
                // TODO: Throw a proper error here
                fatalError("PQHandle should not be invalid")
                //throw new InvalidOperationException("PQHandle should not be invalid")
            }
        }
        _pq.initialize()
    }

    private func donePriorityQ() {
        _pq = nil
    }

    /// <summary>
    /// Delete any degenerate faces with only two edges.  walkDirtyRegions()
    /// will catch almost all of these, but it won't catch degenerate faces
    /// produced by splice operations on already-processed edges.
    /// The two places this can happen are in FinishLeftRegions(), when
    /// we splice in a "temporary" edge produced by connectRightVertex(),
    /// and in CheckForLeftSplice(), where we splice already-processed
    /// edges to ensure that our dictionary invariants are not violated
    /// by numerical errors.
    /// 
    /// In both these cases it is *very* dangerous to delete the offending
    /// edge at the time, since one of the routines further up the stack
    /// will sometimes be keeping a pointer to that edge.
    /// </summary>
    private func removeDegenerateFaces() {
        mesh.forEachFace { f in
            let e = f.anEdge!
            assert(e.Lnext != e)
            
            if (e.Lnext.Lnext == e) {
                // A face with only two edges
                Geom.addWinding(e.Onext, e)
                mesh.delete(e)
            }
        }
    }

    /// <summary>
    /// ComputeInterior computes the planar arrangement specified
    /// by the given contours, and further subdivides this arrangement
    /// into regions.  Each region is marked "inside" if it belongs
    /// to the polygon, according to the rule given by windingRule.
    /// Each interior region is guaranteed to be monotone.
    /// </summary>
    internal func computeInterior() {
        // Each vertex defines an event for our sweep line. Start by inserting
        // all the vertices in a priority queue. Events are processed in
        // lexicographic order, ie.
        // 
        // e1 < e2  iff  e1.x < e2.x || (e1.x == e2.x && e1.y < e2.y)
        removeDegenerateEdges()
        initPriorityQ()
        removeDegenerateFaces()
        initEdgeDict()

        var vNext: Vertex?
        
        while let v = _pq.extractMin() {
            while (true) {
                vNext = _pq.minimum()
                if (vNext == nil || !Geom.vertEq(vNext!, v)) {
                    break
                }
                
                // Merge together all vertices at exactly the same location.
                // This is more efficient than processing them one at a time,
                // simplifies the code (see connectLeftDegenerate), and is also
                // important for correct handling of certain degenerate cases.
                // For example, suppose there are two identical edges A and B
                // that belong to different contours (so without this code they would
                // be processed by separate sweep events). Suppose another edge C
                // crosses A and B from above. When A is processed, we split it
                // at its intersection point with C. However this also splits C,
                // so when we insert B we may compute a slightly different
                // intersection point. This might leave two edges with a small
                // gap between them. This kind of error is especially obvious
                // when using boundary extraction (BoundaryOnly).
                vNext = _pq.extractMin()
                spliceMergeVertices(v.anEdge, vNext!.anEdge)
            }
            sweepEvent(v)
        }

        doneEdgeDict()
        donePriorityQ()

        removeDegenerateFaces()
        mesh.check()
    }
}
