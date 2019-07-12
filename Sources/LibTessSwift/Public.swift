//
//  Protocols.swift
//  Pods
//
//  Created by Luiz Fernando Silva on 01/03/17.
//
//

import libtess2
import simd

/// The default 3D vector representation used by LibTessSwift.
public typealias CVector3 = float3

extension CVector3: Vector2Representable {
    
}

extension CVector3: Vector3Representable {
    
}

/// Specifies a type that has x and y fields that represent a 2D cartesian
/// coordinate.
public protocol Vector2Representable {
    /// X component of coordinate.
    var x: TESSreal { get }
    
    /// Y component of coordinate.
    var y: TESSreal { get }
}

/// Specifies a type that has x, y and z fields that represent a 2D cartesian
/// coordinate.
///
/// Compatible with Vector2 representations when ignoring 'z' component.
public protocol Vector3Representable: Vector2Representable {
    /// Z component of coordinate.
    var z: TESSreal { get }
}
