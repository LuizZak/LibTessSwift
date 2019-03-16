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

public struct Color {
    static var white = Color(red: 1, green: 1, blue: 1, alpha: 1)
    
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
}

public struct PolygonPoint: CustomStringConvertible {
    public var x: CGFloat, y: CGFloat, z: CGFloat
    public var color: Color
    
    init(x: CGFloat, y: CGFloat, z: CGFloat, color: Color) {
        self.x = x
        self.y = y
        self.z = z
        self.color = color
    }
    
    public var description: String {
        return "\(x), \(y), \(z)"
    }
}

public class Polygon {
    
    var points: [PolygonPoint] = []
    
    public var orientation: ContourOrientation = ContourOrientation.original

    public init() {
        
    }
    
    public init(_ points: [PolygonPoint], orientation: ContourOrientation = .original) {
        self.points = points
        self.orientation = orientation
    }
}

fileprivate extension Color {
    
    static func fromRGBA(red: Int, green: Int, blue: Int, alpha: Int = 255) -> Color {
        let rf = CGFloat(red) / 255
        let gf = CGFloat(green) / 255
        let bf = CGFloat(blue) / 255
        let af = CGFloat(alpha) / 255
        
        return Color(red: rf, green: gf, blue: bf, alpha: af)
    }
}

public class PolygonSet {
    var polygons: [Polygon] = []
    public var hasColors = false
}

public class DataLoader {
    public class Asset {
        public var name: String
        public var path: URL
        public var polygon: PolygonSet?
        
        init(name: String, path: URL) {
            self.name = name
            self.path = path
        }
    }
    
    public static func LoadDat(reader: FileReader) throws -> PolygonSet {
        var points: [PolygonPoint] = []
        let polys = PolygonSet()
        
        var currentColor = Color.white
        var currentOrientation = ContourOrientation.original
        
        while var line = reader.readLine() {
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
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
            
            let tokenizer = TokenizerLexer<FullToken<TestDataToken>>(input: line)
            
            if tokenizer.tokenType(is: .force) {
                try tokenizer.advance(overTokenType: .force)
                if tokenizer.tokenType(is: .cw) {
                    try tokenizer.advance(overTokenType: .cw)
                    currentOrientation = .clockwise
                } else {
                    try tokenizer.advance(overTokenType: .ccw)
                    currentOrientation = .counterClockwise
                }
            } else if tokenizer.tokenType(is: .color) {
                try tokenizer.advance(overTokenType: .color)
                
                let tokens = tokenizer.allTokens().filter { $0.tokenType != .comma }
                
                if tokens.contains(where: { $0.tokenType != .integer }) {
                    throw DataError.invalidInputData(message: "Expected 3 or 4 integer values for color values")
                }
                
                if tokens.count == 3 {
                    let r = Int(tokens[0].value)!
                    let g = Int(tokens[1].value)!
                    let b = Int(tokens[2].value)!
                    
                    currentColor = Color.fromRGBA(red: r, green: g, blue: b)
                    polys.hasColors = true
                } else if tokens.count == 4 {
                    let r = Int(tokens[0].value)!
                    let g = Int(tokens[1].value)!
                    let b = Int(tokens[2].value)!
                    let a = Int(tokens[3].value)!
                    
                    currentColor = Color.fromRGBA(red: r, green: g, blue: b, alpha: a)
                    polys.hasColors = true
                } else {
                    throw DataError.invalidInputData(message: "Expected 3 or 4 color values, found \(tokens.count)")
                }
            } else {
                var x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0
                
                var xyz = try tokenizer.allTokens()
                    .filter { $0.tokenType != .comma }
                    .map { token -> CGFloat in
                        if let double = Double(token.value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            return CGFloat(double)
                        }
                        
                        throw LexerError.syntaxError(
                            token.range?.lowerBound ?? tokenizer.lexer.inputIndex,
                            "Expected floating-point value, received \(token.value)"
                        )
                    }
                
                if xyz.count != 0 {
                    if xyz.count > 0 {
                        x = CGFloat(xyz[0])
                    }
                    if xyz.count > 1 {
                        y = CGFloat(xyz[1])
                    }
                    if xyz.count > 2 {
                        z = CGFloat(xyz[2])
                    }
                    
                    points.append(PolygonPoint(x: x, y: y, z: z, color: currentColor))
                } else {
                    throw DataError.invalidInputData(message: "Expected to find at least one floating-point for xyz coordinates")
                }
            }
        }
        
        if points.count > 0 {
            let p = Polygon(points)
            p.orientation = currentOrientation
            polys.polygons.append(p)
        }
        
        return polys
    }
    
    var _assets: [String: Asset] = [:]
    
    public var assetNames: [String] {
        get {
            return Array(_assets.keys)
        }
    }

    public init() throws {
        
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
            
            _assets[fileName] = Asset(name: fileName, path: path)
        }
    }
    
    public func getAsset(name: String) throws -> Asset? {
        guard let asset = _assets[name] else {
            return nil
        }
        
        if asset.polygon == nil {
            let reader = try FileReader(fileUrl: asset.path)
            
            asset.polygon = try DataLoader.LoadDat(reader: reader)
        }
        
        return asset
    }
    
    enum DataError: Error {
        case invalidInputData(message: String)
    }
}

private enum TestDataToken: TokenProtocol {
    /// Grammar for floating point numbers.
    ///
    /// Format grammar representation:
    ///
    /// ```
    /// float-grammar:
    ///     '-'? [0-9]+ ('.' [0-9]+)? (('E' | 'e') '-'? [0-9]+)?
    /// ```
    fileprivate static let floatGrammar: GrammarRule =
            ["-"]
            + GrammarRule.digit+
            + ["." + GrammarRule.digit+]
            + [("E" | "e") + ["-"] + GrammarRule.digit+]
    
    case eof
    case comma
    case force
    case color
    case cw
    case ccw
    case integer
    case float
    
    static var eofToken: TestDataToken = .eof
    
    var tokenString: String {
        switch self {
        case .eof:
            return ""
        case .comma:
            return ","
        case .force:
            return "force"
        case .color:
            return "color"
        case .cw:
            return "cw"
        case .ccw:
            return "ccw"
        case .integer:
            return "<integer>"
        case .float:
            return "<float>"
        }
    }
    
    func length(in lexer: Lexer) -> Int {
        switch self {
        case .eof:
            return 0
        case .comma:
            return 1
        case .cw:
            return 2
        case .ccw:
            return 3
        case .force, .color:
            return 5
        case .integer:
            return (GrammarRule.digit+).maximumLength(in: lexer) ?? 0
        case .float:
            return TestDataToken.floatGrammar.maximumLength(in: lexer) ?? 0
        }
    }
    
    static func tokenType(at lexer: Lexer) -> TestDataToken? {
        
        if lexer.checkNext(matches: ",") {
            return .comma
        }
        
        if lexer.checkNext(matches: "force") {
            return .force
        }
        if lexer.checkNext(matches: "color") {
            return .color
        }
        if lexer.checkNext(matches: "cw") {
            return .cw
        }
        if lexer.checkNext(matches: "ccw") {
            return .ccw
        }
        
        if lexer.safeNextCharPasses(with: Lexer.isDigit) {
            let backtracker = lexer.backtracker()
            lexer.advance(while: Lexer.isDigit)
            
            if !lexer.safeIsNextChar(equalTo: ".") {
                return .integer
            }
            
            backtracker.backtrack()
        }
        
        if TestDataToken.floatGrammar.passes(in: lexer) {
            return .float
        }
        
        return .eof
    }
}
