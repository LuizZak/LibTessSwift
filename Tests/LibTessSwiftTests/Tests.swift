import Foundation
import XCTest
import LibTessSwift
import MiniLexer

class Tests: XCTestCase {
    
    static var _loader: DataLoader = try! DataLoader()
    
    public struct TestCaseData: CustomStringConvertible {
        public var assetName: String
        public var assetURL: URL
        public var winding: WindingRule
        public var elementSize: Int
        
        public var description: String {
            return "\(winding), \(assetName), \(assetURL), \(elementSize)"
        }
    }

    public class TestData {
        public var elementSize: Int
        public var indices: [Int]
        
        init(indices: [Int], elementSize: Int) {
            self.indices = indices
            self.elementSize = elementSize
        }
    }
    
    public var OutputTestData = false
    
    public func testTesselate_WithSingleTriangle_ProducesSameTriangle() throws {
        let data = "0,0,0\n0,1,0\n1,1,0"
        var indices: [Int] = []
        let expectedIndices = [0, 1, 2]
        
        let tess = try setupTess(withString: data)
        
        try tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements![i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)
    }
    
    // From https://github.com/memononen/libtess2/issues/14
    public func testTesselate_WithThinQuad_DoesNotCrash() throws {
        let data = "9.5,7.5,-0.5\n9.5,2,-0.5\n9.5,2,-0.4999999701976776123\n9.5,7.5,-0.4999999701976776123"
        
        let tess = try setupTess(withString: data)
        
        try tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
    }
    
    
    // From https://github.com/speps/LibTessDotNet/issues/1
    public func testTesselate_WithIssue1Quad_ReturnsSameResultAsLibtess2() throws {
        let data = "50,50\n300,50\n300,200\n50,200"
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2, 1, 0, 3 ]
        
        let tess = try setupTess(withString: data)
        
        try tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements![i * 3 + j]
                indices.append(index)
            }
        }
        
        XCTAssertEqual(expectedIndices, indices)
    }
    
    // From https://github.com/speps/LibTessDotNet/issues/1
    public func testTesselate_WithNoEmptyPolygonsTrue_RemovesEmptyPolygons() throws {
        let data = "2,0,4\n2,0,2\n4,0,2\n4,0,0\n0,0,0\n0,0,4"
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2, 2, 3, 4, 3, 1, 5 ]
        
        let tess = try setupTess(withString: data)
        tess.noEmptyPolygons = true
        try tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements![i * 3 + j]
                indices.append(index)
            }
        }
        XCTAssertEqual(expectedIndices, indices)
    }
    
    public func testTesselate_CalledTwiceOnSameInstance_DoesNotCrash() throws {
        let data = "0,0,0\n0,1,0\n1,1,0"
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2 ]
        
        let reader = FileReader(string: data)
        
        let pset = try DataLoader.loadData(reader: reader)
        let tess = TessC()!
        
        // Call once
        PolyConvert.toTessC(pset: pset, tess: tess)
        try tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements![i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)

        // Call twice
        PolyConvert.toTessC(pset: pset, tess: tess)
        try tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)

        indices.removeAll()
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements![i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)
    }
    
    public func testTessellate_WithAssets_ReturnsExpectedTriangulation() {
        
        // Multi-task the test
        let queue = OperationQueue()
        
        for data in Tests.getTestCaseData() {
            queue.addOperation {
                autoreleasepool {
                    do {
                        let pset = try Tests._loader.getAsset(name: data.assetName)!.polygon!
                        let tess = TessC()!
                        PolyConvert.toTessC(pset: pset, tess: tess)
                        try! tess.tessellate(windingRule: data.winding,
                                             elementType: .polygons,
                                             polySize: data.elementSize)
                        
                        let resourceUrl =
                            data.assetURL
                                .deletingPathExtension()
                                .appendingPathExtension("testdat")
                        
                        let reader = try FileReader(fileUrl: resourceUrl)
                        
                        guard let testData = Tests.parseTestData(data.winding, data.elementSize, reader) else {
                            XCTFail("Unexpected empty data for test result for \(data.assetName)")
                            return
                        }
                        
                        XCTAssertEqual(testData.elementSize, data.elementSize)
                        
                        var indices: [Int] = []
                        
                        for i in 0..<tess.elementCount {
                            for j in 0..<data.elementSize {
                                let index = tess.elements![i * data.elementSize + j]
                                indices.append(index)
                            }
                        }
                        
                        if(testData.indices != indices) {
                            XCTFail("Failed test: winding: \(data.winding.rawValue) file: \(data.assetName) element size: \(data.elementSize)")
                            print(testData.indices, indices)
                        }
                    } catch {
                        XCTFail("Failed test: winding: \(data.winding.rawValue) file: \(data.assetName) element size: \(data.elementSize) - caught unexpected error \(error)")
                    }
                }
            }
        }
        
        let expec = expectation(description: "")
        
        // Sometimes, Xcode complains about a blocked main thread during tests
        // Use XCTest's expectation to wrap the operation above
        DispatchQueue.global().async {
            queue.waitUntilAllOperationsAreFinished()
            expec.fulfill()
        }
        
        waitForExpectations(timeout: 200, handler: nil)
    }
}

extension Tests {
    
    static func getTestCaseData() -> [TestCaseData] {
        var data: [TestCaseData] = []
        
        let windings: [WindingRule] = [
            .evenOdd,
            .nonZero,
            .positive,
            .negative,
            .absGeqTwo
        ]
        
        for winding in windings {
            for name in Tests._loader.assetNames {
                guard let asset = Tests._loader.assets[name] else {
                    continue
                }
                
                data.append(TestCaseData(assetName: name,
                                         assetURL: asset.path,
                                         winding: winding,
                                         elementSize: 3))
            }
        }
        
        return data
    }
    
    public static func parseTestData(_ winding: WindingRule,
                                     _ elementSize: Int,
                                     _ reader: FileReader) -> TestData? {
        
        var lines: [String] = []
        var found = false
        
        while true {
            let breakOut: Bool = autoreleasepool {
                guard let line = reader.readLine() else {
                    return true
                }
                
                if found && line.isEmpty {
                    return true
                }
                if found {
                    lines.append(line)
                }
                if line == "\(winding.description) \(elementSize)" {
                    found = true
                }
                
                return false
            }
            
            if breakOut {
                break
            }
        }
        
        if !found {
            return nil
        }
        
        var indices: [Int] = []
        indices.reserveCapacity(lines.count * elementSize)
        for line in lines {
            let lexer = Lexer(input: line)
            
            var parts: [Int] = []
            while !lexer.isEof() {
                parts.append(try! lexer.lexInt())
                lexer.skipWhitespace()
            }
            
            if parts.count != elementSize {
                continue
            }
            for part in parts {
                indices.append(part)
            }
        }
        
        return TestData(indices: indices, elementSize: elementSize)
    }
    
    func setupTess(withString string: String) throws -> TessC {
        let reader = FileReader(string: string)
        
        let pset = try DataLoader.loadData(reader: reader)
        let tess = TessC()!
        
        PolyConvert.toTessC(pset: pset, tess: tess)
        
        return tess
    }
}
