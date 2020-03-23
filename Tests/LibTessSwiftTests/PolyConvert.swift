import LibTessSwift
import simd

class PolyConvert {
    static func toTessC(pset: PolygonSet, tess: TessC) {
        for poly in pset.polygons {
            var v: [CVector3] = []
            
            for p in poly.points {
                let vertex = CVector3(x: p.x, y: p.y, z: p.z)
                v.append(vertex)
            }
            
            tess.addContour(v, poly.orientation)
        }
    }
}
