import LibTessSwift
import simd

class PolyConvert {
    
    public static func ToTessC(pset: PolygonSet, tess: TessC) {
        for poly in pset.polygons {
            var v: [CVector3] = []
            
            for p in poly.points {
                let vertex = CVector3(x: p.x, y: p.y, z: p.z)
                v.append(vertex)
            }
            
            tess.addContour(v, poly.orientation)
        }
    }
    
    public static func FromTessC(tess: TessC) -> PolygonSet {
        let output = PolygonSet()
        
        guard let elements = tess.elements, let vertices = tess.vertices else {
            return output
        }
        
        for i in 0..<tess.elementCount {
            let poly = Polygon()
            
            for j in 0..<3 {
                let index = elements[i * 3 + j]
                if (index == -1) {
                    continue
                }
                let v = PolygonPoint(
                    x: vertices[index].x,
                    y: vertices[index].y,
                    z: vertices[index].z,
                    color: Color.white
                )
                poly.points.append(v)
            }
            output.polygons.append(poly)
        }
        return output
    }
}
