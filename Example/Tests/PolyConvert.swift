//
//  PolyConvert.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import LibTessSwift

class PolyConvert: NSObject {
    
    public static func ToTess(pset: PolygonSet, tess: Tess) {
        for poly in pset.polygons {
            var v: [ContourVertex] = []
            
            for p in poly.points {
                let vertex = ContourVertex(Position: Vector3(x: Real(p.X), y: Real(p.Y), z: Real(p.Z)),
                                           Data: p.Color)
                v.append(vertex)
            }
            
            tess.addContour(v, poly.Orientation)
        }
    }

    public static func FromTess(tess: Tess) -> PolygonSet {
        let output = PolygonSet()
        
        for i in 0..<tess.elementCount {
            let poly = Polygon()
            
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                if (index == -1) {
                    continue
                }
                let v = PolygonPoint(
                    X: CGFloat(tess.vertices[index].position.x),
                    Y: CGFloat(tess.vertices[index].position.y),
                    Z: 0,
                    Color: UIColor.white
                )
                poly.points.append(v)
            }
            output.polygons.append(poly)
        }
        return output
    }
}
