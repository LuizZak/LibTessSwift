import Foundation
import XCTest
import LibTessSwift

class Tests: XCTestCase {
    
    static var _loader: DataLoader = try! DataLoader()
    
    public struct TestCaseData: CustomStringConvertible {
        public var AssetName: String
        public var AssetURL: URL
        public var Winding: WindingRule
        public var ElementSize: Int
        
        public var description: String {
            return "\(Winding), \(AssetName), \(AssetURL), \(ElementSize)"
        }
    }

    public class TestData {
        public var ElementSize: Int
        public var Indices: [Int]
        
        init(indices: [Int], elementSize: Int) {
            self.Indices = indices
            self.ElementSize = elementSize
        }
    }
    
    public var OutputTestData = false
    
    public func testTesselate_WithSingleTriangle_ProducesSameTriangle() throws {
        let data = "0,0,0\n0,1,0\n1,1,0"
        var indices: [Int] = []
        let expectedIndices = [0, 1, 2]
        
        let tess = try setupTess(withString: data)
        
        tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)
    }
    
    // From https://github.com/memononen/libtess2/issues/14
    public func testTesselate_WithThinQuad_DoesNotCrash() throws {
        let data = "9.5,7.5,-0.5\n9.5,2,-0.5\n9.5,2,-0.4999999701976776123\n9.5,7.5,-0.4999999701976776123"
        
        let tess = try setupTess(withString: data)
        
        tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
    }
    
    
    // From https://github.com/speps/LibTessDotNet/issues/1
    public func testTesselate_WithIssue1Quad_ReturnsSameResultAsLibtess2() throws {
        let data = "50,50\n300,50\n300,200\n50,200"
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2, 1, 0, 3 ]
        
        let tess = try setupTess(withString: data)
        
        tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
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
        tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                indices.append(index)
            }
        }
        XCTAssertEqual(expectedIndices, indices)
    }
    
    public func testTesselate_CalledTwiceOnSameInstance_DoesNotCrash() throws {
        let data = "0,0,0\n0,1,0\n1,1,0"
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2 ]
        
        let reader = DDStreamReader.fromString(data)
        
        let pset = try DataLoader.LoadDat(reader: reader)
        let tess = Tess()
        
        // Call once
        PolyConvert.ToTess(pset: pset, tess: tess)
        tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)

        // Call twice
        PolyConvert.ToTess(pset: pset, tess: tess)
        tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)

        indices.removeAll()
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)
    }
    
    public func testTessellate_WithAssets_ReturnsExpectedTriangulation() {
        
        // Multi-task the test
        let queue = OperationQueue()
        
        for data in GetTestCaseData() {
            queue.addOperation {
                autoreleasepool {
                    do {
                        let pset = try Tests._loader.GetAsset(name: data.AssetName)!.Polygons!
                        let tess = Tess()
                        PolyConvert.ToTess(pset: pset, tess: tess)
                        tess.tessellate(windingRule: data.Winding,
                                        elementType: .polygons,
                                        polySize: data.ElementSize)
                        
                        let resourceUrl =
                            data.AssetURL
                                .deletingPathExtension()
                                .appendingPathExtension("testdat")
                        
                        let reader = try DDUnbufferedFileReader(fileUrl: resourceUrl)
                        
                        guard let testData = self.ParseTestData(data.Winding, data.ElementSize, reader) else {
                            XCTFail("Unexpected empty data for test result for \(data.AssetName)")
                            return
                        }
                        
                        XCTAssertEqual(testData.ElementSize, data.ElementSize)
                        
                        var indices: [Int] = []
                        
                        for i in 0..<tess.elementCount {
                            for j in 0..<data.ElementSize {
                                let index = tess.elements[i * data.ElementSize + j]
                                indices.append(index)
                            }
                        }
                        
                        if(testData.Indices != indices) {
                            XCTFail("Failed test: winding: \(data.Winding.rawValue) file: \(data.AssetName) element size: \(data.ElementSize)")
                            print(testData.Indices, indices)
                        }
                    } catch {
                        XCTFail("Failed test: winding: \(data.Winding.rawValue) file: \(data.AssetName) element size: \(data.ElementSize) - caught unexpected error \(error)")
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
    
    func GetTestCaseData() -> [TestCaseData] {
        var data: [TestCaseData] = []
        
        let windings: [WindingRule] = [
            .evenOdd,
            .nonZero,
            .positive,
            .negative,
            .absGeqTwo
        ]
        
        for winding in windings {
            for name in Tests._loader.AssetNames {
                guard let asset = Tests._loader._assets[name] else {
                    continue
                }
                
                data.append(TestCaseData(AssetName: name,
                                         AssetURL: asset.Path,
                                         Winding: winding,
                                         ElementSize: 3))
            }
        }
        
        return data
    }
    
    public func ParseTestData(_ winding: WindingRule, _ elementSize: Int, _ reader: StreamLineReader) -> TestData? {
        var lines: [String] = []
        
        var found = false
        
        while true {
            
            let breakOut: Bool = autoreleasepool {
                guard var line = reader.readLine() else {
                    return true
                }
                
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if (found && line.isEmpty) {
                    return true
                }
                if (found) {
                    lines.append(line)
                }
                let parts = line.components(separatedBy: " ")
                if(parts.count < 2) {
                    return false
                }
                
                if (parts.first == winding.rawValue && Int(parts.last!) == elementSize) {
                    found = true
                }
                
                return false
            }
            
            if(breakOut) {
                break
            }
        }
        
        var indices: [Int] = []
        for line in lines {
            let parts = line.components(separatedBy: " ")
            if (parts.count != elementSize) {
                continue
            }
            for part in parts {
                indices.append(Int(part)!)
            }
        }
        if (found) {
            return TestData(indices: indices, elementSize: elementSize)
        }
        return nil
    }
    
    func setupTess(withString string: String) throws -> Tess {
        let reader = DDStreamReader.fromString(string)
        
        let pset = try DataLoader.LoadDat(reader: reader)
        let tess = Tess()
        
        PolyConvert.ToTess(pset: pset, tess: tess)
        
        return tess
    }
}
