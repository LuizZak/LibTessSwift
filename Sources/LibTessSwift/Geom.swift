//
//  Geom.swift
//  Squishy2048
//
//  Created by Luiz Fernando Silva on 27/02/17.
//  Copyright © 2017 Luiz Fernando Silva. All rights reserved.
//

internal class Geom {
    static func isWindingInside(_ rule: WindingRule, _ n: Int) -> Bool {
        switch (rule) {
            case WindingRule.evenOdd:
                return (n & 1) == 1
            case WindingRule.nonZero:
                return n != 0
            case WindingRule.positive:
                return n > 0
            case WindingRule.negative:
                return n < 0
            case WindingRule.absGeqTwo:
                return n >= 2 || n <= -2
        }
    }

    static func vertCCW(_ u: Vertex, _ v: Vertex, _ w: Vertex) -> Bool {
        return (u._s * (v._t - w._t) + v._s * (w._t - u._t) + w._s * (u._t - v._t)) >= 0.0
    }
    static func vertEq(_ lhs: Vertex, _ rhs: Vertex) -> Bool {
        return lhs._s == rhs._s && lhs._t == rhs._t
    }
    static func vertLeq(_ lhs: Vertex, _ rhs: Vertex) -> Bool {
        return (lhs._s < rhs._s) || (lhs._s == rhs._s && lhs._t <= rhs._t)
    }

    /// <summary>
    /// Given three vertices u,v,w such that VertLeq(u,v) && VertLeq(v,w),
    /// evaluates the t-coord of the edge uw at the s-coord of the vertex v.
    /// Returns v->t - (uw)(v->s), ie. the signed distance from uw to v.
    /// If uw is vertical (and thus passes thru v), the result is zero.
    /// 
    /// The calculation is extremely accurate and stable, even when v
    /// is very close to u or w.  In particular if we set v->t = 0 and
    /// let r be the negated result (this evaluates (uw)(v->s)), then
    /// r is guaranteed to satisfy MIN(u->t,w->t) <= r <= MAX(u->t,w->t).
    /// </summary>
    static func edgeEval(_ u: Vertex, _ v: Vertex, _ w: Vertex) -> Real {
        assert(vertLeq(u, v) && vertLeq(v, w))
        
        let gapL: Real = v._s - u._s as Real
        let gapR: Real = w._s - v._s as Real
        
        /* vertical line */
        if (gapL + gapR <= 0.0) {
            return 0
        }
        
        if (gapL < gapR) {
            let k = gapL / (gapL + gapR) as Real
            let t1 = v._t - u._t as Real
            let t2 = u._t - w._t as Real
            
            return t1 + t2 * k
        } else {
            let k = gapR / (gapL + gapR) as Real
            let t1 = v._t - w._t as Real
            let t2 = w._t - u._t as Real
            
            return t1 + t2 * k
        }
    }

    /// <summary>
    /// Returns a number whose sign matches edgeEval(u,v,w) but which
    /// is cheaper to evaluate. Returns > 0, == 0 , or < 0
    /// as v is above, on, or below the edge uw.
    /// </summary>
    static func edgeSign(_ u: Vertex, _ v: Vertex, _ w: Vertex) -> Real {
        assert(vertLeq(u, v) && vertLeq(v, w))

        let gapL = v._s - u._s
        let gapR = w._s - v._s
        
        if gapL + gapR > 0.0 {
            let t1 = (v._t - w._t) * gapL
            let t2 = (v._t - u._t) * gapR
            return t1 + t2
        }
        /* vertical line */
        return 0
    }

    static func transLeq(_ lhs: Vertex, _ rhs: Vertex) -> Bool {
        return (lhs._t < rhs._t) || (lhs._t == rhs._t && lhs._s <= rhs._s)
    }

    static func transEval(_ u: Vertex, _ v: Vertex, _ w: Vertex) -> Real {
        assert(transLeq(u, v) && transLeq(v, w))
        
        let gapL = (v._t - u._t)
        let gapR = (w._t - v._t)

        if gapL + gapR > 0.0 {
            if gapL < gapR {
                let k = gapL / (gapL + gapR)
                let s1 = v._s - u._s
                let s2 = u._s - w._s
                return s1 + s2 * k
            } else {
                let k = gapR / (gapL + gapR)
                let s1 = v._s - w._s
                let s2 = w._s - u._s
                return s1 + s2 * k
            }
        }
        /* vertical line */
        return 0
    }

    static func transSign(_ u: Vertex, _ v: Vertex, _ w: Vertex) -> Real {
        assert(transLeq(u, v) && transLeq(v, w))
        
        let gapL = v._t - u._t
        let gapR = w._t - v._t
        
        if (gapL + gapR > 0.0) {
            let s1 = ((v._s - w._s) * gapL) as Real
            let s2 = ((v._s - u._s) * gapR) as Real
            return s1 + s2
        }
        /* vertical line */
        return 0
    }

    static func edgeGoesLeft(_ e: Edge) -> Bool {
        return vertLeq(e._Dst!, e._Org!)
    }

    static func edgeGoesRight(_ e: Edge) -> Bool {
        return vertLeq(e._Org!, e._Dst!)
    }

    static func VertL1dist(u: Vertex, v: Vertex) -> Real {
        let s = abs(u._s - v._s) as Real
        let t = abs(u._t - v._t) as Real
        return s + t
    }

    static func addWinding(_ eDst: Edge, _ eSrc: Edge) {
        eDst._winding += eSrc._winding
        eDst._Sym._winding += eSrc._Sym._winding
    }

    static func interpolate(_ a: Real, _ x: Real, _ b: Real, _ y: Real) -> Real {
        var a = a
        var b = b
        if (a < 0.0) {
            a = 0.0
        }
        if (b < 0.0) {
            b = 0.0
        }
        
        return ((a <= b) ? ((b == 0.0) ? ((x+y) / 2.0)
                : (x + (y-x) * (a/(a+b))))
                : (y + (x-y) * (b/(a+b))))
    }
    
    /// <summary>
    /// Given edges (o1,d1) and (o2,d2), compute their point of intersection.
    /// The computed point is guaranteed to lie in the intersection of the
    /// bounding rectangles defined by each edge.
    /// </summary>
    static func edgeIntersect(o1: Vertex, d1: Vertex, o2: Vertex, d2: Vertex, v: Vertex) {
        var o1 = o1
        var d1 = d1
        var o2 = o2
        var d2 = d2
        // This is certainly not the most efficient way to find the intersection
        // of two line segments, but it is very numerically stable.
        // 
        // Strategy: find the two middle vertices in the VertLeq ordering,
        // and interpolate the intersection s-value from these.  Then repeat
        // using the transLeq ordering to find the intersection t-value.
        
        if (!vertLeq(o1, d1)) { swap(&o1, &d1) }
        if (!vertLeq(o2, d2)) { swap(&o2, &d2) }
        if (!vertLeq(o1, o2)) { swap(&o1, &o2); swap(&d1, &d2) }

        if (!vertLeq(o2, d1)) {
            // Technically, no intersection -- do our best
            v._s = (o2._s + d1._s) / 2.0
        } else if (vertLeq(d1, d2)) {
            // Interpolate between o2 and d1
            var z1 = edgeEval(o1, o2, d1)
            var z2 = edgeEval(o2, d1, d2)
            if (z1 + z2 < 0.0) {
                z1 = -z1
                z2 = -z2
            }
            v._s = interpolate(z1, o2._s, z2, d1._s)
        } else {
            // Interpolate between o2 and d2
            var z1 = edgeSign(o1, o2, d1)
            var z2 = -edgeSign(o1, d2, d1)
            if (z1 + z2 < 0.0) {
                z1 = -z1
                z2 = -z2
            }
            v._s = interpolate(z1, o2._s, z2, d2._s)
        }

        // Now repeat the process for t

        if (!transLeq(o1, d1)) { swap(&o1, &d1) }
        if (!transLeq(o2, d2)) { swap(&o2, &d2) }
        if (!transLeq(o1, o2)) { swap(&o1, &o2); swap(&d1, &d2) }
        
        if (!transLeq(o2, d1)) {
            // Technically, no intersection -- do our best
            v._t = (o2._t + d1._t) / 2.0
        } else if (transLeq(d1, d2)) {
            // Interpolate between o2 and d1
            var z1 = transEval(o1, o2, d1)
            var z2 = transEval(o2, d1, d2)
            if (z1 + z2 < 0.0) {
                z1 = -z1
                z2 = -z2
            }
            v._t = interpolate(z1, o2._t, z2, d1._t)
        } else {
            // Interpolate between o2 and d2
            var z1 = transSign(o1, o2, d1)
            var z2 = -transSign(o1, d2, d1)
            if (z1 + z2 < 0.0) {
                z1 = -z1
                z2 = -z2
            }
            v._t = interpolate(z1, o2._t, z2, d2._t)
        }
    }
}
