# LibTessSwift

[![CI Status](http://img.shields.io/travis/LuizZak/LibTessSwift.svg?style=flat)](https://travis-ci.org/LuizZak/LibTessSwift)

A Swift wrapper on top of [Libtess2](https://github.com/memononen/Libtess2) for polygon triangulation.

Tests where derived from [LibTessDotNet](https://github.com/speps/LibTessDotNet) library, which is also a port of the library above.

Also, a fix for an issue of 0-area polygons from libtess2 that was fixed by LibTessDotNet is also merged in. 

Supports self-intersecting polygons and polygons with holes.

## Sample Usage

This is a sample wrapper over TessC to process polygons and return result in vertices/indices pairs.

```swift
func process(polygon: [MyVector]) -> (vertices: [MyVector], indices: [Int])? {
    let polygon: [MyVector] = ... // This should be an array of vertices - must have at least an `x` and `y` coordinate pairs!

    let tess = Tess()

    // Size of polygon (number of points per face)
    let polySize = 3

    // Map from MyVector to ContourVertex (LibTessSwift's vector representation)
    let contour = polygon.map {
        ContourVertex(Position(x: $0.x, y: $0.y, z: 0.0))
    }

    // Add the contour to LibTess
    tess.addContour(contour)

    // Tessellate, now
    tess.tessellate(windingRule: .evenOdd, elementType: .polygons, polySize: polySize)

    // Collect resulting vector
    var result: [MyVector] = []
    var indices: [Int] = []
    
    // Extract vertices
    for vertex in tess.vertices! {
        result.append(MyVector(x: vertex.x, y: vertex.y))
    }
    
    // Extract each index for each polygon triangle found
    for i in 0..<tess.elementCount {
        for j in 0..<polySize {
            let index = tess.elements![i * polySize + j]
            if index == -1 {
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

## Installation

LibTessSwift is available as a [Swift Package Manager](https://swift.org).

## Author

LuizZak

## License

LibTessSwift is available under the MIT license. See the LICENSE file for more info.
