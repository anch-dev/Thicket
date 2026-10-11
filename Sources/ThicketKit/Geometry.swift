import Foundation

/// Minimal geometry types so this module stays free of CoreGraphics/UIKit.
/// Coordinates follow UIKit: origin top-left, y grows downward, units are points.
public struct Vec2: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to o: Vec2) -> Double { (self - o).length }
}

public struct Rect2: Codable, Equatable, Hashable {
    public var origin: Vec2
    public var size: Vec2

    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = Vec2(x, y)
        size = Vec2(width, height)
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
    public var width: Double { size.x }
    public var height: Double { size.y }

    public func contains(_ p: Vec2) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }

    /// Maps a 0...1 normalized point into this rect.
    public func point(normalized n: Vec2) -> Vec2 { Vec2(minX + n.x * width, minY + n.y * height) }

    /// Inverse of `point(normalized:)`.
    public func normalized(_ p: Vec2) -> Vec2 {
        Vec2(width > 0 ? (p.x - minX) / width : 0, height > 0 ? (p.y - minY) / height : 0)
    }

    public func intersects(_ o: Rect2) -> Bool {
        minX < o.maxX && o.minX < maxX && minY < o.maxY && o.minY < maxY
    }
}
