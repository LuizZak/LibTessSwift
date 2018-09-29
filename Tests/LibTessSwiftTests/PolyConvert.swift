//
//  PolyConvert.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import LibTessSwift

class PolyConvert: NSObject {
    
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

    public static func fromTess(tess: Tess) -> PolygonSet {
        let output = PolygonSet()
        
        for i in 0..<tess.elementCount {
            let poly = Polygon()
            
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                if (index == -1) {
                    continue
                }
                let v = PolygonPoint(
                    x: CGFloat(tess.vertices[index].position.x),
                    y: CGFloat(tess.vertices[index].position.y),
                    z: 0,
                    color: Color.white
                )
                poly.points.append(v)
            }
            output.polygons.append(poly)
        }
        return output
    }
}
