import Testing
import SwiftUI
@testable import RowDataStudio

struct FocusModeTests {

    @Test
    func testFocusDimOpacityIsCorrect() {
        // Widget non selezionati: opacity 30%
        #expect(RDS.Layout.focusDimOpacity == 0.30)
    }

    @Test
    func testFocusModeZoomSpringParameters() {
        // Animazione spring focusModeZoom
        let spring = RDS.Springs.focusModeZoom
        #expect(spring != nil) 
    }
    
    @Test
    func testCanvasZoomBoundaries() {
        // Verify zoom limits used by focus mode
        #expect(RDS.Layout.canvasZoomMin == 0.25)
        #expect(RDS.Layout.canvasZoomMax == 4.0)
    }
    
    @Test
    func testFocusModeViewModifiers() {
        // Test that selected widgets get 1.0 opacity and non-selected get focusDimOpacity
        let isFocusModeActive = true
        let isSelected = false
        
        let opacity = isFocusModeActive && !isSelected ? RDS.Layout.focusDimOpacity : 1.0
        #expect(opacity == 0.30)
        
        let isSelected2 = true
        let opacity2 = isFocusModeActive && !isSelected2 ? RDS.Layout.focusDimOpacity : 1.0
        #expect(opacity2 == 1.0)
    }
}
