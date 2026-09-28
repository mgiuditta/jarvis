import SwiftUI
import Testing
@testable import JarvisCore

struct ColorHexTests {
    @Test(arguments: ["#9B5CFF", "#000000", "#FFFFFF", "#090909", "#12AB34"])
    func hexRoundTrips(hex: String) {
        #expect(Color(hex: hex).hex == hex)
    }

    @Test func invalidHexFallsBackToDefaultPurple() {
        #expect(Color(hex: "zz").hex == "#9B5CFF")
    }
}
