import Foundation
import XCTest
import LibTessSwift

class Tests: XCTestCase {
    
    static var _loader: DataLoader = try! DataLoader()
    
    var OutputTestData = false
    
    func testTesselate_WithSingleTriangle_ProducesSameTriangle() throws {
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
    func testTesselate_WithThinQuad_DoesNotCrash() throws {
        let data = "9.5,7.5,-0.5\n9.5,2,-0.5\n9.5,2,-0.4999999701976776123\n9.5,7.5,-0.4999999701976776123"
        
        let tess = try setupTess(withString: data)
        
        tess.tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3)
    }
    
    
    // From https://github.com/speps/LibTessDotNet/issues/1
    func testTesselate_WithIssue1Quad_ReturnsSameResultAsLibtess2() throws {
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
    func testTesselate_WithNoEmptyPolygonsTrue_RemovesEmptyPolygons() throws {
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
    
    func testTesselate_CalledTwiceOnSameInstance_DoesNotCrash() throws {
        let data = "0,0,0\n0,1,0\n1,1,0"
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2 ]
        
        let reader = FileReader(string: data)
        
        let pset = try DataLoader.LoadDat(reader: reader)
        let tess = Tess()
        
        // Call once
        PolyConvert.toTess(pset: pset, tess: tess)
        tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3)
        
        for i in 0..<tess.elementCount {
            for j in 0..<3 {
                let index = tess.elements[i * 3 + j]
                indices.append(index)
            }
        }

        XCTAssertEqual(expectedIndices, indices)

        // Call twice
        PolyConvert.toTess(pset: pset, tess: tess)
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
    
    func testTessellate_WithAssets_ReturnsExpectedTriangulation() throws {
        
        let fixtures = try getTestCaseFixtures()
        
        // Multi-task the test
        let queue = OperationQueue()
        
        for fixture in fixtures {
            queue.addOperation {
                autoreleasepool {
                    let testCase = fixture.testCase
                    let testData = fixture.testData
                    
                    let tess = Tess()
                    PolyConvert.toTess(pset: fixture.polygon, tess: tess)
                    tess.tessellate(windingRule: testCase.winding,
                                    elementType: .polygons,
                                    polySize: testCase.elementSize)
                    
                    XCTAssertEqual(testData.elementSize, testCase.elementSize)
                    
                    var indices: [Int] = []
                    
                    for i in 0..<tess.elementCount {
                        for j in 0..<testCase.elementSize {
                            let index = tess.elements[i * testCase.elementSize + j]
                            indices.append(index)
                        }
                    }
                    
                    if testData.indices != indices {
                        XCTFail("Failed test: winding: \(testCase.winding.rawValue) file: \(testCase.assetName) element size: \(testCase.elementSize)")
                        print(testData.indices, indices)
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

// MARK: - Test fixture loading
extension Tests {
    
    func getTestCaseFixtures() throws -> [TestFixture] {
        return try getTestCaseData().map { testCase in
            let pset = try Tests._loader.getAsset(name: testCase.assetName)!.polygon!
            
            let resourceUrl =
                testCase.assetURL
                    .deletingPathExtension()
                    .appendingPathExtension("testdat")
            
            let reader = try FileReader(fileUrl: resourceUrl)
            
            guard let testData = parseTestData(testCase.winding, testCase.elementSize, reader) else {
                throw TestError.failedToLoadFixture(name: testCase.assetName)
            }
            
            return TestFixture(testCase: testCase, polygon: pset, testData: testData)
        }
    }
    
    func getTestCaseData() -> [TestCase] {
        var data: [TestCase] = []
        
        let windings: [WindingRule] = [
            .evenOdd,
            .nonZero,
            .positive,
            .negative,
            .absGeqTwo
        ]
        
        for winding in windings {
            for name in Tests._loader.assetNames {
                guard let asset = Tests._loader._assets[name] else {
                    continue
                }
                
                data.append(TestCase(assetName: name,
                                         assetURL: asset.path,
                                         winding: winding,
                                         elementSize: 3))
            }
        }
        
        return data
    }
    
    func parseTestData(_ winding: WindingRule, _ elementSize: Int, _ reader: FileReader) -> TestCaseData? {
        
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
            return TestCaseData(indices: indices, elementSize: elementSize)
        }
        return nil
    }
    
    func setupTess(withString string: String) throws -> Tess {
        let reader = FileReader(string: string)
        
        let pset = try DataLoader.LoadDat(reader: reader)
        let tess = Tess()
        
        PolyConvert.toTess(pset: pset, tess: tess)
        
        return tess
    }
}

// MARK: - Structures
extension Tests {
    enum TestError: Error {
        case failedToLoadFixture(name: String)
    }
    
    struct TestFixture {
        var testCase: TestCase
        var polygon: PolygonSet
        var testData: Tests.TestCaseData
    }
    
    struct TestCase: CustomStringConvertible {
        var assetName: String
        var assetURL: URL
        var winding: WindingRule
        var elementSize: Int
        
        var description: String {
            return "\(winding), \(assetName), \(assetURL), \(elementSize)"
        }
    }
    
    class TestCaseData {
        var elementSize: Int
        var indices: [Int]
        
        init(indices: [Int], elementSize: Int) {
            self.indices = indices
            self.elementSize = elementSize
        }
    }
}
