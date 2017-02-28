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
                let vertex = ContourVertex(Position: Vec3(X: p.X, Y: p.Y, Z: p.Z),
                                           Data: p.Color)
                v.append(vertex)
            }
            
            tess.AddContour(v, poly.Orientation)
        }
    }

    public static func FromTess(tess: Tess) -> PolygonSet {
        let output = PolygonSet()
        
        for i in 0..<tess.ElementCount {
            let poly = Polygon()
            
            for j in 0..<3 {
                let index = tess.Elements[i * 3 + j]
                if (index == -1) {
                    continue
                }
                let v = PolygonPoint(
                    X: tess.Vertices[index].Position.X,
                    Y: tess.Vertices[index].Position.Y,
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
