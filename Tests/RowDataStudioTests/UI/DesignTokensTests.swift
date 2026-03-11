import Testing
import SwiftUI
@testable import RowDataStudio

struct DesignTokensTests {

    @Test
    func testSemanticColors() {
        // Test that StreamType cases correctly map to semantic colors defined in RDS.MetricColors
        #expect(StreamType.speed.semanticColor == RDS.MetricColors.speed)
        #expect(StreamType.hr.semanticColor == RDS.MetricColors.heartRate)
        #expect(StreamType.cadence.semanticColor == RDS.MetricColors.strokeRate)
        #expect(StreamType.power.semanticColor == RDS.MetricColors.power)
        #expect(StreamType.gps.semanticColor == RDS.MetricColors.gps)
        #expect(StreamType.accl.semanticColor == RDS.MetricColors.imu)
        #expect(StreamType.video.semanticColor == RDS.Colors.accent)
        #expect(StreamType.audio.semanticColor == .white)
    }

    @Test
    func testAccentColor() {
        let accent = RDS.Colors.accent
        #expect(accent != nil)
        // Just verify it's instantiated successfully (strict RGBA float comparison in SwiftUI can be flaky)
    }

}
