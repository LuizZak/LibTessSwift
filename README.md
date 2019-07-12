# LibTessSwift

[![Build Status](https://dev.azure.com/luiz-fs/LibTessSwift/_apis/build/status/LuizZak.LibTessSwift?branchName=master)](https://dev.azure.com/luiz-fs/LibTessSwift/_build/latest?definitionId=1&branchName=master)

A Swift wrapper on top of [Libtess2](https://github.com/memononen/Libtess2) for polygon triangulation.

Tests where derived from [LibTessDotNet](https://github.com/speps/LibTessDotNet) library, which is also a port of the library above.

Also, a fix for an issue of 0-area polygons from libtess2 that was fixed by LibTessDotNet is also merged in. 

Supports self-intersecting polygons and polygons with holes.

## Sample Usage

This is a sample wrapper over TessC to process polygons and return resultin vertices/indices pairs.

```swift
func process(polygon: [MyVector]) throws -> (vertices: [MyVector], indices: [Int])? {
    let polygon: [MyVector] = ... // This should be an array of vertices - must have at least an `x` and `y` coordinate pairs!

    guard let tess = TessC() else {
        print("Something went wrong while initializing TessC! :c")
        return nil
    }

    // Size of polygon (number of points per face)
    let polySize = 3

    // Map from MyVector to CVector3 (LibTessSwift's vector representation)
    let contour = polygon.map {
        CVector3(x: TESSreal($0.x), y: TESSreal($0.y), z: 0.0)
    }

    // Add the contour to LibTess
    tess.addContour(contour)

    // Tesselate - if no errors are thrown, we're good!
    try tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: polySize)

    // Collect resulting vector
    var result: [MyVector] = []
    var indices: [Int] = []
    
    // Extract vertices
    for vertex in tess.vertices! {
        result.append(MyVector(x: vertex.x, y: vertex.y))
    }
    
    // Extract each index for each polygon triangle found
    for i in 0..<tess.elementCount
    {
        for j in 0..<polySize
        {
            let index = tess.elements![i * polySize + j]
            if (index == -1) {
                continue
            }
            indices.append(index)
        }
    }

    return (result, indices)
}

// Use away!
guard let (verts, indices) = try process(myVerts) else {
    return
}

MyRenderer.drawPolygon(verts: verts, indices: indices)
```

## Requirements

## Installation

LibTessSwift is available as a [Swift Package Manager](https://swift.org/package-manager/):

```ruby
.package(url: "https://github.com/LuizZak/LibTessSwift.git", .exact("0.8.0"))
```

## Author

LuizZak

## License

LibTessSwift is available under the MIT license. See the LICENSE file for more info.
