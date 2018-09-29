import LibTessSwift

class PolyConvert {
    
    public static func toTess(pset: PolygonSet, tess: Tess) {
        for poly in pset.polygons {
            var v: [ContourVertex] = []
            
            for p in poly.points {
                let vertex = ContourVertex(Position: Vector3(x: Real(p.x), y: Real(p.y), z: Real(p.z)),
                                           Data: p.color)
                v.append(vertex)
            }
            
            tess.addContour(v, poly.orientation)
        }
    }
}
