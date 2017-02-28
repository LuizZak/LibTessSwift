import UIKit
import XCTest
import LibTessSwift

class Tests: XCTestCase {
    
    static var _loader: DataLoader = DataLoader()
    
    public struct TestCaseData: CustomStringConvertible {
        public var AssetName: String;
        public var Winding: WindingRule;
        public var ElementSize: Int;
        
        public var description: String {
            return "\(Winding), \(AssetName), \(ElementSize)";
        }
    }

    public class TestData {
        public var ElementSize: Int;
        public var Indices: [Int];
        
        init(indices: [Int], elementSize: Int) {
            self.Indices = indices
            self.ElementSize = elementSize
        }
    }
    
    public var OutputTestData = false;
    public var TestDataPath = "./" // Path.Combine("..", "..", "TessBed", "TestData");
    
    public func testTesselate_WithSingleTriangle_ProducesSameTriangle() throws {
        let data = "0,0,0\n0,1,0\n1,1,0";
        var indices: [Int] = []
        let expectedIndices = [0, 1, 2]
        
        let tess = try setupTess(withString: data);
        
        tess.Tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3);
        
        for i in 0..<tess.ElementCount {
            for j in 0..<3 {
                let index = tess.Elements[i * 3 + j];
                indices.append(index);
            }
        }

        XCTAssertEqual(expectedIndices, indices)
    }
    
    // From https://github.com/memononen/libtess2/issues/14
    public func testTesselate_WithThinQuad_DoesNotCrash() throws {
        let data = "9.5,7.5,-0.5\n9.5,2,-0.5\n9.5,2,-0.4999999701976776123\n9.5,7.5,-0.4999999701976776123";
        
        let tess = try setupTess(withString: data);
        
        tess.Tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3);
    }
    
    
    // From https://github.com/speps/LibTessDotNet/issues/1
    public func testTesselate_WithIssue1Quad_ReturnsSameResultAsLibtess2() throws {
        let data = "50,50\n300,50\n300,200\n50,200";
        var indices: [Int] = [];
        let expectedIndices = [ 0, 1, 2, 1, 0, 3 ];
        
        let tess = try setupTess(withString: data);
        
        tess.Tessellate(windingRule: WindingRule.evenOdd, elementType: ElementType.polygons, polySize: 3);
        
        for i in 0..<tess.ElementCount {
            for j in 0..<3 {
                let index = tess.Elements[i * 3 + j];
                indices.append(index);
            }
        }
        
        XCTAssertEqual(expectedIndices, indices);
    }
    
    // From https://github.com/speps/LibTessDotNet/issues/1
    public func testTesselate_WithNoEmptyPolygonsTrue_RemovesEmptyPolygons() throws {
        let data = "2,0,4\n2,0,2\n4,0,2\n4,0,0\n0,0,0\n0,0,4";
        var indices: [Int] = []
        let expectedIndices = [ 0, 1, 2, 2, 3, 4, 3, 1, 5 ]
        
        let tess = try setupTess(withString: data);
        tess.NoEmptyPolygons = true;
        tess.Tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3);
        
        for i in 0..<tess.ElementCount {
            for j in 0..<3 {
                let index = tess.Elements[i * 3 + j];
                indices.append(index);
            }
        }
        XCTAssertEqual(expectedIndices, indices);
    }
    
    public func testTesselate_CalledTwiceOnSameInstance_DoesNotCrash() throws {
        let data = "0,0,0\n0,1,0\n1,1,0";
        var indices: [Int] = [];
        let expectedIndices = [ 0, 1, 2 ]
        
        let stream = InputStream(data: data.data(using: .utf8)!)
        stream.open()
        defer {
            stream.close()
        }
        
        let pset = try DataLoader.LoadDat(resourceStream: stream);
        let tess = Tess();
        
        // Call once
        PolyConvert.ToTess(pset: pset, tess: tess);
        tess.Tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3);
        
        for i in 0..<tess.ElementCount {
            for j in 0..<3 {
                let index = tess.Elements[i * 3 + j];
                indices.append(index);
            }
        }

        XCTAssertEqual(expectedIndices, indices);

        // Call twice
        PolyConvert.ToTess(pset: pset, tess: tess);
        tess.Tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: 3);

        indices.removeAll()
        for i in 0..<tess.ElementCount {
            for j in 0..<3 {
                let index = tess.Elements[i * 3 + j];
                indices.append(index);
            }
        }

        XCTAssertEqual(expectedIndices, indices);
    }
    
    public func testTessellate_WithAssets_ReturnsExpectedTriangulation() {
        
        let bundle = Bundle(for: type(of: self))
        
        // Multi-task the test
        let queue = OperationQueue()
        
        for data in GetTestCaseData() {
            queue.addOperation {
                autoreleasepool {
                    do {
                        var pset = try Tests._loader.GetAsset(name: data.AssetName)!.Polygons!
                        var tess = Tess()
                        PolyConvert.ToTess(pset: pset, tess: tess)
                        tess.Tessellate(windingRule: data.Winding, elementType: .polygons, polySize: data.ElementSize);
                        
                        guard let resourceName = bundle.path(forResource: data.AssetName, ofType: "testdat") else {
                            print("Could not find resulting test asset \(data.AssetName).testdat for test data \(data.AssetName).dat")
                            return
                        }
                        
                        let stream = InputStream(fileAtPath: resourceName)!
                        stream.open()
                        defer {
                            stream.close()
                        }
                        
                        guard let testData = self.ParseTestData(data.Winding, data.ElementSize, stream) else {
                            XCTFail("Unexpected empty data for test result for \(data.AssetName)");
                            return
                        }
                        
                        XCTAssertEqual(testData.ElementSize, data.ElementSize)
                        
                        var indices: [Int] = []
                        
                        for i in 0..<tess.ElementCount {
                            for j in 0..<data.ElementSize {
                                let index = tess.Elements[i * data.ElementSize + j];
                                indices.append(index);
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
                data.append(TestCaseData(AssetName: name, Winding: winding, ElementSize: 3));
            }
        }
        
        return data;
    }
    
    public func ParseTestData(_ winding: WindingRule, _ elementSize: Int, _ resourceStream: InputStream) -> TestData? {
        var lines: [String] = []
        
        var found = false;
        
        let reader = DDStreamReader(inputStream: resourceStream)
        
        while var line = reader.readLine() {
            line = line.trimmingCharacters(in: .whitespacesAndNewlines);
            if (found && line.isEmpty) {
                break
            }
            if (found) {
                lines.append(line)
            }
            let parts = line.components(separatedBy: " ");
            if(parts.count < 2) {
                continue
            }
            
            if (parts.first == winding.rawValue && Int(parts.last!) == elementSize) {
                found = true;
            }
        }
        
        var indices: [Int] = []
        for line in lines {
            let parts = line.components(separatedBy: " ")
            if (parts.count != elementSize) {
                continue
            }
            for part in parts {
                indices.append(Int(part)!);
            }
        }
        if (found) {
            return TestData(indices: indices, elementSize: elementSize)
        }
        return nil;
    }
    
    /*
    [Test, TestCaseSource("GetTestCaseData")]
    public void Tessellate_WithAsset_ReturnsExpectedTriangulation(TestCaseData data) {
        var pset = _loader.GetAsset(data.AssetName).Polygons;
        var tess = new Tess();
        PolyConvert.ToTess(pset, tess);
        tess.Tessellate(data.Winding, ElementType.Polygons, data.ElementSize);

        var resourceName = Assembly.GetExecutingAssembly().GetName().Name + ".TestData." + data.AssetName + ".testdat";
        var testData = ParseTestData(data.Winding, data.ElementSize, Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName));
        Assert.IsNotNull(testData);
        Assert.AreEqual(testData.ElementSize, data.ElementSize);

        var indices = new List<int>();
        for (int i = 0; i < tess.ElementCount; i++) {
            for (int j = 0; j < data.ElementSize; j++) {
                int index = tess.Elements[i * data.ElementSize + j];
                indices.Add(index);
            }
        }

        Assert.AreEqual(testData.Indices, indices.ToArray());
    }

    public static void GenerateTestData() {
        foreach (var name in _loader.AssetNames) {
            var pset = _loader.GetAsset(name).Polygons;

            var lines = new List<string>();
            var indices = new List<int>();

            foreach (WindingRule winding in Enum.GetValues(typeof(WindingRule))) {
                var tess = new Tess();
                PolyConvert.ToTess(pset, tess);
                tess.Tessellate(winding, ElementType.Polygons, 3);

                lines.Add(string.Format("{0} {1}", winding, 3));
                for (int i = 0; i < tess.ElementCount; i++) {
                    indices.Clear();
                    for (int j = 0; j < 3; j++) {
                        int index = tess.Elements[i * 3 + j];
                        indices.Add(index);
                    }
                    lines.Add(string.Join(" ", indices));
                }
                lines.Add("");
            }

            File.WriteAllLines(Path.Combine(TestDataPath, name + ".testdat"), lines);
        }
    }
    */
    
    func setupTess(withString string: String) throws -> Tess {
        let stream = InputStream(data: string.data(using: .utf8)!)
        stream.open()
        defer {
            stream.close()
        }
        
        let pset = try DataLoader.LoadDat(resourceStream: stream);
        let tess = Tess();
        
        PolyConvert.ToTess(pset: pset, tess: tess);
        
        return tess
    }
}
