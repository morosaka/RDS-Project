// UI/DesignSystem/GlowButton.swift v1.0.0
/**
 * Chromeless button — no background, no border, just light.
 * Source: design-language-details.md §5.2
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-11 - Initial implementation (Phase 8a.2).
 */

import SwiftUI

public struct GlowButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    public init(icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(RDS.Colors.textPrimary.opacity(isHovered ? 1.0 : 0.45))
            .contentShape(Rectangle().inset(by: -8))  // larger hit area
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
