import SwiftUI

// MARK: - Design System Constants
struct DesignSystem {
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        
        // Semantic spacing
        static let cardPadding: CGFloat = medium
        static let sectionSpacing: CGFloat = large
        static let elementSpacing: CGFloat = small
        static let buttonPadding: CGFloat = medium
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 20
    }
    
    // MARK: - Colors
    struct Colors {
        static let primary = Color.blue
        static let secondary = Color.gray
        static let success = Color.green
        static let danger = Color.red
        static let warning = Color.orange
        
        // Background colors
        static let cardBackground = Color(.systemBackground)
        static let sectionBackground = Color(.secondarySystemBackground)
        static let menuBackground = Color(.systemBackground)
        
        // Text colors
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let inverseText = Color.white
    }
    
    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let headline = Font.headline.weight(.medium)
        static let body = Font.body
        static let caption = Font.caption
        static let button = Font.headline.weight(.semibold)
    }
    
    // MARK: - Shadows
    struct Shadow {
        static let card = (color: Color.black.opacity(0.1), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let menu = (color: Color.black.opacity(0.2), radius: CGFloat(10), x: CGFloat(0), y: CGFloat(4))
    }
}

// MARK: - View Extensions for Design System
extension View {
    func cardStyle() -> some View {
        self
            .padding(DesignSystem.Spacing.cardPadding)
            .background(DesignSystem.Colors.cardBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .shadow(
                color: DesignSystem.Shadow.card.color,
                radius: DesignSystem.Shadow.card.radius,
                x: DesignSystem.Shadow.card.x,
                y: DesignSystem.Shadow.card.y
            )
    }
    
    func primaryButton() -> some View {
        self
            .font(DesignSystem.Typography.button)
            .foregroundColor(DesignSystem.Colors.inverseText)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.primary)
            .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    func secondaryButton() -> some View {
        self
            .font(DesignSystem.Typography.button)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.sectionBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    func sectionSpacing() -> some View {
        self.padding(.bottom, DesignSystem.Spacing.sectionSpacing)
    }
}
