import Testing
import Foundation
@testable import JarvisCore

struct OrbZoneTests {
    let screen = CGRect(x: 0, y: 25, width: 1500, height: 900)

    @Test func nearestUsesScreenThirds() {
        #expect(OrbZone.nearest(to: CGPoint(x: 10, y: 30), in: screen) == OrbZone(col: 0, row: 0))
        #expect(OrbZone.nearest(to: CGPoint(x: 750, y: 475), in: screen) == OrbZone(col: 1, row: 1))
        #expect(OrbZone.nearest(to: CGPoint(x: 1500, y: 925), in: screen) == OrbZone(col: 2, row: 2))  // the far edge clamps in
        #expect(OrbZone.nearest(to: CGPoint(x: -50, y: 2000), in: screen) == OrbZone(col: 0, row: 2))
    }

    @Test func originSitsOnEdgesOrCenter() {
        let s = CGSize(width: 100, height: 100)
        #expect(OrbZone.bottomRight.origin(for: s, in: screen) == CGPoint(x: 1400, y: 25))
        #expect(OrbZone(col: 1, row: 2).origin(for: s, in: screen) == CGPoint(x: 700, y: 825))
        #expect(OrbZone(col: 1, row: 1).origin(for: s, in: screen) == CGPoint(x: 700, y: 425))
    }

    @Test func indexRoundTripsAndNamesAreUnique() {
        for z in OrbZone.all { #expect(OrbZone(index: z.index) == z) }
        #expect(OrbZone(index: 9) == nil)
        #expect(Set(OrbZone.all.map(\.name)).count == 9)
        #expect(!OrbZone.bottomRight.cardBelow && OrbZone(col: 0, row: 1).cardBelow)
    }
}
