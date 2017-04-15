//
//  PolyConvert.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import LibTessSwift
import simd

class PolyConvert {
    
    public static func ToTessC(pset: PolygonSet, tess: TessC) {
        for poly in pset.polygons {
            var v: [CVector3] = []
            
            for p in poly.points {
                let vertex = CVector3(x: TESSreal(p.X), y: TESSreal(p.Y), z: TESSreal(p.Z))
                v.append(vertex)
            }
            
            tess.addContour(v, poly.Orientation)
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
                    X: CGFloat(vertices[index].x),
                    Y: CGFloat(vertices[index].y),
                    Z: CGFloat(vertices[index].z),
                    Color: UIColor.white
                )
                poly.points.append(v)
            }
            output.polygons.append(poly)
        }
        return output
    }
}
