#ifndef TRIANGLE_H_ESIZ1HBQ
#define TRIANGLE_H_ESIZ1HBQ


/** @file src/triangle.h
 * Implement the possibility to create triangles, that must be combined in a mesh/world.
 */

#include <array>
#include <functional>
#include <stdexcept>

#include "vector.h"

/// A triangle is a set of 3 points, the order of the points defines the orientation.
class triangle {
public:
    triangle(const coord& p0, const coord& p1, const coord& p2) : points{p0, p1, p2} 
    {
        if(!spans_area(p0, p1, p2))
            throw std::invalid_argument{"Provided points do not span an area, hence "
                                        "they form not a triangle!"};
    }

    triangle(const triangle&) = default;
    triangle& operator=(const triangle&) = default;

    triangle(triangle&&) = default;
    triangle& operator=(triangle&&) = default;

    const coord& p0() const noexcept { return points[0]; }
    const coord& p1() const noexcept { return points[1]; }
    const coord& p2() const noexcept { return points[2]; }

    /// Surface normal of the triangle, not normalized
    coord normal() const noexcept { return cross(p1() - p0(), p2() - p1()); }

private:
    std::array<std::reference_wrapper<const coord>, 3> points;
};


#endif /* end of include guard: TRIANGLE_H_ESIZ1HBQ */