//
//  DataLoader.swift
//  LibTessSwift
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import LibTessSwift
import MiniLexer

struct Color {
    static var white = Color(red: 1, green: 1, blue: 1, alpha: 1)
    
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float
    
    fileprivate static func fromRGBA(red: Int, green: Int, blue: Int, alpha: Int = 255) -> Color {
        let rf = Float(red) / 255
        let gf = Float(green) / 255
        let bf = Float(blue) / 255
        let af = Float(alpha) / 255
        
        return Color(red: rf, green: gf, blue: bf, alpha: af)
    }
}

struct PolygonPoint: CustomStringConvertible {
    var x: Float, y: Float, z: Float
    var color: Color
    
    init(x: Float, y: Float, z: Float, color: Color) {
        self.x = x
        self.y = y
        self.z = z
        self.color = color
    }
    
    var description: String {
        return "\(x), \(y), \(z)"
    }
}

class Polygon {
    var points: [PolygonPoint] = []
    var orientation: ContourOrientation = ContourOrientation.original
    
    init() {
        
    }
    
    init<S: Sequence>(_ s: S, orientation: ContourOrientation = .original) where S.Iterator.Element == PolygonPoint {
        points = Array(s)
        self.orientation = orientation
    }
}

class PolygonSet {
    var polygons: [Polygon] = []
    var hasColors = false
}

class DataLoader {
    class Asset {
        var name: String
        var path: URL
        var polygon: PolygonSet?
        
        init(name: String, path: URL) {
            self.name = name
            self.path = path
        }
    }
    
    static func loadData(reader: FileReader) throws -> PolygonSet {
        var points: [PolygonPoint] = []
        let polys = PolygonSet()
        
        var currentColor = Color.white
        var currentOrientation = ContourOrientation.original
        
        
        let trimCharacterSet = CharacterSet
            .whitespacesAndNewlines
            // Deal with a weird zero-width space character in input files which
            // I cannot remove directly from those files.
            .union(CharacterSet(charactersIn: "\u{FEFF}"))
        
        while var line = reader.readLine() {
            line = line.trimmingCharacters(in: trimCharacterSet)
            
            // Comment
            if line.hasPrefix("//") || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            
            if line.isEmpty {
                if points.count > 0 {
                    let p = Polygon(points, orientation: currentOrientation)
                    currentOrientation = ContourOrientation.original
                    polys.polygons.append(p)
                    points.removeAll()
                }
                continue
            }
            
            let lexer = Lexer(input: line)
            
            if lexer.advanceIf(equals: "force") {
                lexer.skipWhitespace()
                
                if lexer.checkNext(matches: "cw") {
                    currentOrientation = .clockwise
                } else {
                    currentOrientation = .counterClockwise
                }
            } else if lexer.advanceIf(equals: "color") {
                lexer.skipWhitespace()
                
                var integers: [Int] = []
                while !lexer.isEof() {
                    try integers.append(lexer.lexInt())
                    lexer.skipComma()
                }
                
                if integers.count == 3 {
                    let r = integers[0]
                    let g = integers[1]
                    let b = integers[2]
                    
                    currentColor = Color.fromRGBA(red: r, green: g, blue: b)
                    polys.hasColors = true
                } else if integers.count == 4 {
                    let r = integers[0]
                    let g = integers[1]
                    let b = integers[2]
                    let a = integers[3]
                    
                    currentColor = Color.fromRGBA(red: r, green: g, blue: b, alpha: a)
                    polys.hasColors = true
                } else {
                    throw DataError.invalidInputData
                }
            } else {
                var x: Float = 0, y: Float = 0, z: Float = 0
                
                if lexer.isEof() {
                    throw DataError.invalidInputData
                }
                
                x = try lexer.lexFloat()
                lexer.skipComma()
                
                if !lexer.isEof() {
                    y = try lexer.lexFloat()
                    lexer.skipComma()
                    
                    if !lexer.isEof() {
                        z = try lexer.lexFloat()
                    }
                }
                
                points.append(PolygonPoint(x: x, y: y, z: z, color: currentColor))
            }
        }
        
        if !points.isEmpty {
            let p = Polygon(points)
            p.orientation = currentOrientation
            polys.polygons.append(p)
        }
        
        return polys
    }
    
    var assets: [String: Asset] = [:]
    
    var assetNames: [String] {
        get {
            return Array(assets.keys)
        }
    }

    init() throws {
        
        // TODO: This is kinda nasty, but it's the only way to get the files we
        // need until SwiftPM gets a resources story in place
        // (see https://lists.swift.org/pipermail/swift-build-dev/Week-of-Mon-20161114/000742.html)
        let path = (#file as NSString).deletingLastPathComponent
        
        let paths = try FileManager
            .default
            .contentsOfDirectory(at: URL(fileURLWithPath: path),
                                 includingPropertiesForKeys: nil,
                                 options: .skipsSubdirectoryDescendants)
            .filter { $0.pathExtension == "dat" }
        
        for path in paths {
            let name = path.lastPathComponent
            let fileName = name.components(separatedBy: ".").first ?? ""
            
            assets[fileName] = Asset(name: fileName, path: path)
        }
    }
    
    func getAsset(name: String) throws -> Asset? {
        guard let asset = assets[name] else {
            return nil
        }
        
        if asset.polygon == nil {
            let reader = try FileReader(fileUrl: asset.path)
            
            asset.polygon = try DataLoader.loadData(reader: reader)
        }
        
        return asset
    }
    
    enum DataError: Error {
        case invalidInputData
    }
}

extension Lexer {
    func skipComma() {
        skipWhitespace()
        advance(while: { $0 == "," })
        skipWhitespace()
    }
    
    /// Attempts to lex an integer literal from the current point in the text
    /// stream
    ///
    /// Former grammar representation:
    ///
    /// ```
    /// integer-grammar:
    ///     '-'? [0-9]+
    /// ```
    func lexInt() throws -> Int {
        let range = startRange()
        
        // '-'?
        if try peek() == "-" {
            try advance()
        }
        
        // [0-9]+
        try advance(validatingCurrent: Lexer.isDigit)
        while try !isEof() && Lexer.isDigit(peek()) {
            try advance()
        }
        
        guard let int = Int(range.string()) else {
            throw syntaxError("Expected integer value")
        }
        
        return int
    }
    
    /// Attempts to lex a floating point literal from the current point in the
    /// text stream
    ///
    /// Former grammar representation:
    ///
    /// ```
    /// float-grammar:
    ///     '-'? [0-9]+ ('.' [0-9]+)? (('E' | 'e') '-'? [0-9]+)?
    /// ```
    func lexFloat() throws -> Float {
        let range = startRange()
        
        // '-'?
        if try peek() == "-" {
            try advance()
        }
        
        // [0-9]+
        try advance(validatingCurrent: Lexer.isDigit)
        while try !isEof() && Lexer.isDigit(peek()) {
            try advance()
        }
        
        // ('.' [0-9]+)?
        if try !isEof() && peek() == "." {
            try advance()
            try advance(validatingCurrent: Lexer.isDigit)
            while try !isEof() && Lexer.isDigit(peek()) {
                try advance()
            }
        }
        
        // (('E' | 'e') '-'? [0-9]+)?
        if try !isEof() && (peek() == "e" || peek() == "E") {
            try advance()
            
            if try peek() == "-" {
                try advance()
            }
            
            try advance(validatingCurrent: Lexer.isDigit)
            while try !isEof() && Lexer.isDigit(peek()) {
                try advance()
            }
        }
        
        guard let float = Float(range.string()) else {
            throw syntaxError("Expected floating point value")
        }
        
        return float
    }
}
