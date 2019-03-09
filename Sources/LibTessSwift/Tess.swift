//
//  Tess.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 26/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

import simd

public enum WindingRule: String {
    case evenOdd
    case nonZero
    case positive
    case negative
    case absGeqTwo
}

public enum ElementType {
    case polygons
    case connectedPolygons
    case boundaryContours
}

public enum ContourOrientation {
    case original
    case clockwise
    case counterClockwise
}

public struct ContourVertex: CustomStringConvertible {
    public var position: Vector3
    public var data: Any?
    
    public init() {
        position = .zero
        data = nil
    }
    
    public init(Position: Vector3) {
        self.position = Position
        self.data = nil
    }
    
    public init(Position: Vector3, Data: Any?) {
        self.position = Position
        self.data = Data
    }
    
    public var description: String {
        return "\(position), \(data as Any)"
    }
}

public typealias CombineCallback = (_ position: Vector3, _ data: [Any?], _ weights: [Real]) -> Any?

public final class Tess {
    internal var mesh: Mesh!
    internal var _normal: Vector3
    internal var _sUnit: Vector3 = .zero
    internal var _tUnit: Vector3 = .zero

    internal var _bminX: Real
    internal var _bminY: Real
    internal var _bmaxX: Real
    internal var _bmaxY: Real

    internal var windingRule: WindingRule

    internal var _dict: Dict<ActiveRegion>!
    internal var _pq: PriorityQueue<Vertex>!
    internal var _event: Vertex!
    
    internal var _meshCreationContext = MeshCreationContext()
    internal var _regionsPool = Pool<_ActiveRegion>()

    internal var _combineCallback: CombineCallback?

    internal var _vertices: [ContourVertex]!
    internal var _vertexCount: Int
    internal var _elements: [Int]!
    internal var _elementCount: Int
    
    public var normal: Vector3 { get { return _normal } set { _normal = newValue } }
    
    public var SUnitX: Real = 1
    public var SUnitY: Real = 0
#if arch(x86_64) || arch(arm64)
    public var SentinelCoord: Real = 4e150
#else
    public var SentinelCoord: Real = 4e30
#endif

    /// <summary>
    /// If true, will remove empty (zero area) polygons.
    /// </summary>
    public var noEmptyPolygons = false
    
    public var vertices: [ContourVertex]! { get { return _vertices } }
    public var vertexCount: Int { get { return _vertexCount } }
    
    public var elements: [Int]! { get { return _elements } }
    public var elementCount: Int { get { return _elementCount } }
    
    public init() {
        _normal = Vector3.zero
        _bminX = 0
        _bminY = 0
        _bmaxX = 0
        _bmaxY = 0

        windingRule = WindingRule.evenOdd
        mesh = nil
        
        _vertices = nil
        _vertexCount = 0
        _elements = nil
        _elementCount = 0
    }
    
    deinit {
        mesh = nil
        
        _regionsPool.free()
        _meshCreationContext.free()
    }
    
    private func computeNormal(norm: inout Vector3) {
        var v = mesh._vHead.next!

        var minVal: [Real] = [ v.coords.x, v.coords.y, v.coords.z ]
        var minVert: [Vertex] = [ v, v, v ]
        var maxVal: [Real] = [ v.coords.x, v.coords.y, v.coords.z ]
        var maxVert: [Vertex] = [ v, v, v ]
        
        func subMinMax(_ index: Int) -> Real {
            return maxVal[index] - minVal[index]
        }
        
        for v in mesh.makeVertexIterator() {
            if v.coords.x < minVal[0] {
                minVal[0] = v.coords.x
                minVert[0] = v
            }
            if v.coords.y < minVal[1] {
                minVal[1] = v.coords.y
                minVert[1] = v
            }
            if v.coords.z < minVal[2] {
                minVal[2] = v.coords.z
                minVert[2] = v
            }
            if v.coords.x > maxVal[0] {
                maxVal[0] = v.coords.x
                maxVert[0] = v
            }
            if v.coords.y > maxVal[1] {
                maxVal[1] = v.coords.y
                maxVert[1] = v
            }
            if v.coords.z > maxVal[2] {
                maxVal[2] = v.coords.z
                maxVert[2] = v
            }
        }
        
        // Find two vertices separated by at least 1/sqrt(3) of the maximum
        // distance between any two vertices
        var i = 0
        
        if subMinMax(1) > subMinMax(0) {
            i = 1
        }
        
        if subMinMax(2) > subMinMax(i) {
            i = 2
        }
        
        if minVal[i] >= maxVal[i] {
            // All vertices are the same -- normal doesn't matter
            norm = Vector3(x: 0, y: 0, z: 1)
            return
        }
        
        // Look for a third vertex which forms the triangle with maximum area
        // (Length of normal == twice the triangle area)
        var maxLen2: Real = 0
        let v1 = minVert[i]
        let v2 = maxVert[i]
        
        var tNorm: Vector3 = .zero
        var d1 = v1.coords - v2.coords
        
        for v in mesh.makeVertexIterator() {
            let d2 = v.coords - v2.coords
            
            tNorm.x = d1.y * d2.z - d1.z * d2.y
            tNorm.y = d1.z * d2.x - d1.x * d2.z
            tNorm.z = d1.x * d2.y - d1.y * d2.x
            let tLen2 = tNorm.x * tNorm.x + tNorm.y * tNorm.y + tNorm.z * tNorm.z
            
            if tLen2 > maxLen2 {
                maxLen2 = tLen2
                norm = tNorm
            }
        }
        
        if maxLen2 <= 0.0 {
            // All points lie on a single line -- any decent normal will do
            norm = Vector3.zero
            i = Vector3.longAxis(v: &d1)
            norm[i] = 1
        }
    }

    private func checkOrientation() {
        // When we compute the normal automatically, we choose the orientation
        // so that the the sum of the signed areas of all contours is non-negative.
        var area: Real = 0.0
        
        for f in mesh.makeFaceIterator() {
            if f.anEdge!.winding <= 0 {
                continue
            }
            area += MeshUtils.faceArea(f)
        }
        
        if area < 0.0 {
            // Reverse the orientation by flipping all the t-coordinates
            for v in mesh.makeVertexIterator() {
                v.t = -v.t
            }
            
            _tUnit = -_tUnit
        }
    }

    private func projectPolygon() {
        var norm = _normal

        var computedNormal = false
        if norm.x == 0.0 && norm.y == 0.0 && norm.z == 0.0 {
            computeNormal(norm: &norm)
            _normal = norm
            computedNormal = true
        }

        let i = Vector3.longAxis(v: &norm)
        
        _sUnit[i] = 0
        _sUnit[(i + 1) % 3] = SUnitX
        _sUnit[(i + 2) % 3] = SUnitY

        _tUnit[i] = 0
        _tUnit[(i + 1) % 3] = norm[i] > 0.0 ? -SUnitY : SUnitY
        _tUnit[(i + 2) % 3] = norm[i] > 0.0 ? SUnitX : -SUnitX

        // Project the vertices onto the sweep plane
        for v in mesh.makeVertexIterator() {
            v.s = dot(v.coords, _sUnit)
            v.t = dot(v.coords, _tUnit)
        }
        
        if computedNormal {
            checkOrientation()
        }

        // Compute ST bounds.
        var first = true
        
        for v in mesh.makeVertexIterator() {
            if first {
                _bmaxX = v.s
                _bminX = v.s
                
                _bmaxY = v.t
                _bminY = v.t
                first = false
            } else {
                if (v.s < _bminX) { _bminX = v.s }
                if (v.s > _bmaxX) { _bmaxX = v.s }
                if (v.t < _bminY) { _bminY = v.t }
                if (v.t > _bmaxY) { _bmaxY = v.t }
            }
        }
    }

    /// <summary>
    /// TessellateMonoRegion( face ) tessellates a monotone region
    /// (what else would it do??)  The region must consist of a single
    /// loop of half-edges (see mesh.h) oriented CCW.  "Monotone" in this
    /// case means that any vertical line intersects the interior of the
    /// region in a single interval.  
    /// 
    /// Tessellation consists of adding interior edges (actually pairs of
    /// half-edges), to split the region into non-overlapping triangles.
    /// 
    /// The basic idea is explained in Preparata and Shamos (which I don't
    /// have handy right now), although their implementation is more
    /// complicated than this one.  The are two edge chains, an upper chain
    /// and a lower chain.  We process all vertices from both chains in order,
    /// from right to left.
    /// 
    /// The algorithm ensures that the following invariant holds after each
    /// vertex is processed: the untessellated region consists of two
    /// chains, where one chain (say the upper) is a single edge, and
    /// the other chain is concave.  The left vertex of the single edge
    /// is always to the left of all vertices in the concave chain.
    /// 
    /// Each step consists of adding the rightmost unprocessed vertex to one
    /// of the two chains, and forming a fan of triangles from the rightmost
    /// of two chain endpoints.  Determining whether we can add each triangle
    /// to the fan is a simple orientation test.  By making the fan as large
    /// as possible, we restore the invariant (check it yourself).
    /// </summary>
    private func tessellateMonoRegion(_ face: Face) {
        // All edges are oriented CCW around the boundary of the region.
        // First, find the half-edge whose origin vertex is rightmost.
        // Since the sweep goes from left to right, face->anEdge should
        // be close to the edge we want.
        var up = face.anEdge!
        assert(up.Lnext != up && up.Lnext.Lnext != up)
        
        while Geom.vertLeq(up.Dst!, up.Org!) { up = up.Lprev! }
        while Geom.vertLeq(up.Org!, up.Dst!) { up = up.Lnext }
        
        var lo = up.Lprev!
        
        while up.Lnext != lo {
            if Geom.vertLeq(up.Dst, lo.Org) {
                // up.Dst is on the left. It is safe to form triangles from lo.Org.
                // The edgeGoesLeft test guarantees progress even when some triangles
                // are CW, given that the upper and lower chains are truly monotone.
                while lo.Lnext != up && (Geom.edgeGoesLeft(lo.Lnext)
                    || Geom.edgeSign(lo.Org, lo.Dst, lo.Lnext.Dst) <= 0.0) {
                    lo = mesh.connect(lo.Lnext, lo).sym
                }
                lo = lo.Lprev
            } else {
                // lo.Org is on the left.  We can make CCW triangles from up.Dst.
                while lo.Lnext != up && (Geom.edgeGoesRight(up.Lprev)
                    || Geom.edgeSign(up.Dst, up.Org, up.Lprev.Org) >= 0.0) {
                    up = mesh.connect(up, up.Lprev).sym
                }
                up = up.Lnext
            }
        }
        
        // Now lo.Org == up.Dst == the leftmost vertex.  The remaining region
        // can be tessellated in a fan from this leftmost vertex.
        assert(lo.Lnext != up)
        while lo.Lnext.Lnext != up {
            lo = mesh.connect(lo.Lnext, lo).sym
        }
    }

    /// <summary>
    /// TessellateInterior( mesh ) tessellates each region of
    /// the mesh which is marked "inside" the polygon. Each such region
    /// must be monotone.
    /// </summary>
    private func tessellateInterior() {
        for f in mesh.makeFaceIterator() {
            if f.inside {
                tessellateMonoRegion(f)
            }
        }
    }

    /// <summary>
    /// DiscardExterior zaps (ie. sets to nil) all faces
    /// which are not marked "inside" the polygon.  Since further mesh operations
    /// on nil faces are not allowed, the main purpose is to clean up the
    /// mesh so that exterior loops are not represented in the data structure.
    /// </summary>
    private func discardExterior() {
        for f in mesh.makeFaceIterator() {
            if !f.inside {
                mesh.zapFace(f)
            }
        }
    }

    /// <summary>
    /// SetWindingNumber( value, keepOnlyBoundary ) resets the
    /// winding numbers on all edges so that regions marked "inside" the
    /// polygon have a winding number of "value", and regions outside
    /// have a winding number of 0.
    /// 
    /// If keepOnlyBoundary is TRUE, it also deletes all edges which do not
    /// separate an interior region from an exterior one.
    /// </summary>
    private func setWindingNumber(_ value: Int, _ keepOnlyBoundary: Bool) {
        
        for e in mesh.makeEdgeIterator() {
            if e.Rface.inside != e.Lface.inside {
                
                /* This is a boundary edge (one side is interior, one is exterior). */
                e.winding = (e.Lface.inside) ? value : -value
            } else {
                
                /* Both regions are interior, or both are exterior. */
                if !keepOnlyBoundary {
                    e.winding = 0
                } else {
                    mesh.delete(e)
                }
            }
        }
    }
    
    private func getNeighbourFace(_ edge: Edge) -> Int {
        if edge.Rface == nil {
            return MeshUtils.Undef
        }
        if !edge.Rface!.inside {
            return MeshUtils.Undef
        }
        return edge.Rface!.n
    }
    
    private func outputPolymesh(_ elementType: ElementType, _ polySize: Int) {
        var maxFaceCount = 0
        var maxVertexCount = 0
        var faceVerts: Int = 0
        var polySize = polySize

        if polySize < 3 {
            polySize = 3
        }
        // Assume that the input data is triangles now.
        // Try to merge as many polygons as possible
        if polySize > 3 {
            mesh.mergeConvexFaces(maxVertsPerFace: polySize)
        }

        // Mark unused
        for v in mesh.makeVertexIterator() {
            v.n = MeshUtils.Undef
        }
        
        // Create unique IDs for all vertices and faces.
        for f in mesh.makeFaceIterator() {
            f.n = MeshUtils.Undef
            if !f.inside { continue }
            
            if noEmptyPolygons {
                let area = MeshUtils.faceArea(f)
                if abs(area) < Real.leastNonzeroMagnitude {
                    continue
                }
            }
            
            var edge = f.anEdge!
            faceVerts = 0
            repeat {
                let v = edge.Org!
                if v.n == MeshUtils.Undef {
                    v.n = maxVertexCount
                    maxVertexCount += 1
                }
                faceVerts += 1
                edge = edge.Lnext
            } while edge != f.anEdge
            
            assert(faceVerts <= polySize)
            
            f.n = maxFaceCount
            maxFaceCount += 1
        }

        _elementCount = maxFaceCount
        if elementType == ElementType.connectedPolygons {
            maxFaceCount *= 2
        }
        _elements = Array(repeating: 0, count: maxFaceCount * polySize)

        _vertexCount = maxVertexCount
        _vertices = Array(repeating: ContourVertex(Position: .zero, Data: nil), count: _vertexCount)

        // Output vertices.
        for v in mesh.makeVertexIterator() {
            if v.n != MeshUtils.Undef {
                // Store coordinate
                _vertices[v.n].position = v.coords
                _vertices[v.n].data = v.data
            }
        }
        
        // Output indices.
        var elementIndex = 0
        
        for f in mesh.makeFaceIterator() {
            if !f.inside { continue }
            
            if noEmptyPolygons {
                let area = MeshUtils.faceArea(f)
                if abs(area) < Real.leastNonzeroMagnitude {
                    continue
                }
            }
            
            // Store polygon
            var edge = f.anEdge!
            faceVerts = 0
            repeat {
                let v = edge.Org!
                _elements[elementIndex] = v.n
                elementIndex += 1
                faceVerts += 1
                edge = edge.Lnext
            } while edge != f.anEdge
            // Fill unused.
            for _ in faceVerts..<polySize {
                _elements[elementIndex] = MeshUtils.Undef
                elementIndex += 1
            }
            
            // Store polygon connectivity
            if elementType == ElementType.connectedPolygons {
                edge = f.anEdge!
                repeat {
                    _elements[elementIndex] = getNeighbourFace(edge)
                    elementIndex += 1
                    edge = edge.Lnext
                } while edge != f.anEdge
                
                // Fill unused.
                for _ in faceVerts..<polySize {
                    _elements[elementIndex] = MeshUtils.Undef
                    elementIndex += 1
                }
            }
        }
    }
    
    private func outputContours() {
        var startVert = 0
        var vertCount = 0
        
        _vertexCount = 0
        _elementCount = 0
        
        for f in mesh.makeFaceIterator() {
            if !f.inside {
                continue
            }
            
            let start = f.anEdge!
            var edge = f.anEdge!
            repeat {
                _vertexCount += 1
                edge = edge.Lnext
            } while edge != start
            
            _elementCount += 1
        }

        _elements = Array(repeating: 0, count: _elementCount * 2)
        _vertices = Array(repeating: ContourVertex(Position: .zero, Data: nil), count: _vertexCount)

        var vertIndex = 0
        var elementIndex = 0
        
        startVert = 0
        
        for f in mesh.makeFaceIterator() {
            if !f.inside {
                continue
            }
            
            vertCount = 0
            let start = f.anEdge!
            var edge = f.anEdge!
            repeat {
                _vertices[vertIndex].position = edge.Org.coords
                _vertices[vertIndex].data = edge.Org.data
                vertIndex += 1
                vertCount += 1
                edge = edge.Lnext
            } while edge != start
            
            _elements[elementIndex] = startVert
            elementIndex += 1
            _elements[elementIndex] = vertCount
            elementIndex += 1
            
            startVert += vertCount
        }
    }

    private func signedArea(_ vertices: [ContourVertex]) -> Real {
        var area: Real = 0.0
        
        for i in 0..<vertices.count {
            let v0 = vertices[i]
            let v1 = vertices[(i + 1) % vertices.count]

            area += v0.position.x * v1.position.y
            area -= v0.position.y * v1.position.x
        }

        return 0.5 * area
    }

    public func addContour(_ vertices: [ContourVertex]) {
        addContour(vertices, ContourOrientation.original)
    }

    public func addContour(_ vertices: [ContourVertex], _ forceOrientation: ContourOrientation) {
        if mesh == nil {
            mesh = Mesh(context: _meshCreationContext)
        }

        var reverse = false
        if forceOrientation != ContourOrientation.original {
            let area = signedArea(vertices)
            reverse = (forceOrientation == ContourOrientation.clockwise && area < 0.0) || (forceOrientation == ContourOrientation.counterClockwise && area > 0.0)
        }

        var e: Edge! = nil
        for i in 0..<vertices.count {
            if e == nil {
                e = mesh.makeEdge()
                mesh.splice(e, e.sym)
            } else {
                // Create a new vertex and edge which immediately follow e
                // in the ordering around the left face.
                _=mesh.splitEdge(e)
                e = e.Lnext
            }
            
            let index = reverse ? vertices.count - 1 - i : i
            // The new vertex is now e._Org.
            e.Org.coords = vertices[index].position
            e.Org.data = vertices[index].data

            // The winding of an edge says how the winding number changes as we
            // cross from the edge's right face to its left face.  We add the
            // vertices in such an order that a CCW contour will add +1 to
            // the winding number of the region inside the contour.
            e.winding = 1
            e.sym.winding = -1
        }
    }
    
    public func tessellate(windingRule: WindingRule, elementType: ElementType, polySize: Int) {
        tessellate(windingRule: windingRule, elementType: elementType, polySize: polySize, combineCallback: nil)
    }
    
    public func tessellate(windingRule: WindingRule, elementType: ElementType, polySize: Int, combineCallback: CombineCallback?) {
        _normal = Vector3.zero
        _vertices = nil
        _elements = nil

        self.windingRule = windingRule
        _combineCallback = combineCallback

        guard let mesh = mesh else {
            return
        }

        // Determine the polygon normal and project vertices onto the plane
        // of the polygon.
        projectPolygon()

        // ComputeInterior computes the planar arrangement specified
        // by the given contours, and further subdivides this arrangement
        // into regions.  Each region is marked "inside" if it belongs
        // to the polygon, according to the rule given by windingRule.
        // Each interior region is guaranteed be monotone.
        computeInterior()

        // If the user wants only the boundary contours, we throw away all edges
        // except those which separate the interior from the exterior.
        // Otherwise we tessellate all the regions marked "inside".
        if elementType == ElementType.boundaryContours {
            setWindingNumber(1, true)
        } else {
            tessellateInterior()
        }
        
        mesh.check()
        
        if elementType == ElementType.boundaryContours {
            outputContours()
        } else {
            outputPolymesh(elementType, polySize)
        }
        
        self.mesh = nil
        _meshCreationContext.reset()
    }
}
