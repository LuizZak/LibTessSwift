//
//  DataLoader.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import LibTessSwift

public struct PolygonPoint: CustomStringConvertible {
    public var X: CGFloat, Y: CGFloat, Z: CGFloat
    public var Color: UIColor
    
    init(X: CGFloat, Y: CGFloat, Z: CGFloat, Color: UIColor) {
        self.X = X
        self.Y = Y
        self.Z = Z
        self.Color = Color
    }
    
    public var description: String {
        return "\(X), \(Y), \(Z)"
    }
}

public class Polygon {
    
    var points: [PolygonPoint] = []
    
    public var Orientation: ContourOrientation = ContourOrientation.original

    public init() {
        
    }
    
    public init<S: Sequence>(_ s: S, orientation: ContourOrientation = .original) where S.Iterator.Element == PolygonPoint {
        points = Array(s)
        Orientation = orientation
    }
}

fileprivate extension UIColor {
    
    static func fromRGBA(red: Int, green: Int, blue: Int, alpha: Int = 255) -> UIColor {
        let rf = CGFloat(red) / 255
        let gf = CGFloat(green) / 255
        let bf = CGFloat(blue) / 255
        let af = CGFloat(alpha) / 255
        
        return UIColor(red: rf, green: gf, blue: bf, alpha: af)
    }
}

public class PolygonSet {
    var polygons: [Polygon] = []
    public var HasColors = false
}

public class DataLoader {
    public class Asset {
        public var Name: String
        public var Path: String
        public var Polygons: PolygonSet?
        
        init() {
            Name = ""
            Path = ""
        }
        
        init(Name: String, Path: String) {
            self.Name = Name
            self.Path = Path
        }
    }
    
    public static func LoadDat(reader: StreamLineReader) throws -> PolygonSet {
        var points: [PolygonPoint] = []
        let polys = PolygonSet()
        
        var currentColor = UIColor.white
        var currentOrientation = ContourOrientation.original
        
        let separation = CharacterSet.init(charactersIn: " ,\t")
        
        while var line = reader.readLine() {
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if(line.isEmpty) {
                if (points.count > 0) {
                    let p = Polygon(points, orientation: currentOrientation)
                    currentOrientation = ContourOrientation.original
                    polys.polygons.append(p)
                    points.removeAll()
                }
                continue
            }
            // Comment
            if(line.hasPrefix("//") || line.hasPrefix("#") || line.hasPrefix(";")) {
                continue
            }
            
            if(line.hasPrefix("force")) {
                var force = line.components(separatedBy: separation).filter { !$0.isEmpty }
                
                if (force.count == 2) {
                    if(force[1].localizedCaseInsensitiveCompare("cw") == .orderedSame) {
                        currentOrientation = .clockwise
                    }
                    if(force[1].localizedCaseInsensitiveCompare("ccw") == .orderedSame) {
                        currentOrientation = .counterClockwise
                    }
                }
            } else if (line.hasPrefix("color")) {
                var rgba = line.components(separatedBy: separation).filter { !$0.isEmpty }
                
                if (rgba.count != 0) {
                    
                    // rgb
                    if rgba.count == 4, let r = Int(rgba[1]), let g = Int(rgba[2]), let b = Int(rgba[3]) {
                        currentColor = UIColor.fromRGBA(red: r, green: g, blue: b)
                        polys.HasColors = true
                    }
                    
                    // rgba
                    if rgba.count == 5, let r = Int(rgba[1]), let g = Int(rgba[2]), let b = Int(rgba[3]), let a = Int(rgba[4]) {
                        currentColor = UIColor.fromRGBA(red: r, green: g, blue: b, alpha: a)
                        polys.HasColors = true
                    }
                }
            } else {
                var x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0
                
                var xyz = line.components(separatedBy: separation).filter { !$0.isEmpty }
                
                if (xyz.count != 0) {
                    if xyz.count > 0, let value = Double(xyz[0]) {
                        x = CGFloat(value)
                    }
                    if xyz.count > 1, let value = Double(xyz[1]) {
                        y = CGFloat(value)
                    }
                    if xyz.count > 2, let value = Double(xyz[2]) {
                        z = CGFloat(value)
                    }
                    
                    points.append(PolygonPoint(X: x, Y: y, Z: z, Color: currentColor))
                } else {
                    throw DataError.invalidInputData
                }
            }
        }
        
        if (points.count > 0) {
            let p = Polygon(points)
            p.Orientation = currentOrientation
            polys.polygons.append(p)
        }
        
        return polys
    }
    
    var _assets: [String: Asset] = [:]
    
    public var AssetNames: [String] {
        get {
            return Array(_assets.keys)
        }
    }

    public init() {
        
        let bundle = Bundle(for: type(of: self))
        let paths = bundle.paths(forResourcesOfType: ".dat", inDirectory: nil)
        
        for path in paths {
            let name = (path as NSString).lastPathComponent
            let fileName = name.components(separatedBy: ".").first ?? ""
            
            _assets[fileName] = Asset(Name: fileName, Path: path)
        }
    }
    
    public func GetAsset(name: String) throws -> Asset? {
        guard let asset = _assets[name] else {
            return nil
        }
        
        if(asset.Polygons == nil) {
            let reader = try DDUnbufferedFileReader(fileUrl: URL(fileURLWithPath: asset.Path))
            
            asset.Polygons = try DataLoader.LoadDat(reader: reader)
        }
        
        return asset
    }
    
    enum DataError: Error {
        case invalidInputData
    }
}
