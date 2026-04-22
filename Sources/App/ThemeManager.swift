import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case classic = "Classic"
    case matrix = "Matrix"
    case sunset = "Sunset"
    case ocean = "Ocean"
    
    var id: String { self.rawValue }
    
    // MARK: - Primary Colors
    
    var accentColor: Color {
        switch self {
        case .default:  return Color(red: 0.8, green: 0.06, blue: 0.88)   // Audius Purple #CC0FE0
        case .classic:  return Color(red: 0.72, green: 0.45, blue: 0.95)  // Softer classic purple
        case .matrix:   return Color(red: 0.08, green: 1.0, blue: 0.0)    // Matrix Neon Green
        case .sunset:   return Color(red: 1.0, green: 0.45, blue: 0.25)   // Warm coral-amber
        case .ocean:    return Color(red: 0.0, green: 0.82, blue: 0.82)   // Deep teal-cyan
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .default:  return Color(white: 0.03)
        case .classic:  return Color(red: 0.14, green: 0.14, blue: 0.18)
        case .matrix:   return Color.black
        case .sunset:   return Color(red: 0.08, green: 0.05, blue: 0.04)  // Warm dark brown
        case .ocean:    return Color(red: 0.04, green: 0.06, blue: 0.1)   // Deep dark navy
        }
    }
    
    var panelColor: Color {
        switch self {
        case .default:  return Color(white: 0.08)
        case .classic:  return Color(red: 0.18, green: 0.18, blue: 0.22)
        case .matrix:   return Color(white: 0.04)
        case .sunset:   return Color(red: 0.12, green: 0.08, blue: 0.06)
        case .ocean:    return Color(red: 0.06, green: 0.08, blue: 0.14)
        }
    }
    
    // MARK: - Extended Design Tokens
    
    var secondaryTextColor: Color {
        switch self {
        case .matrix:   return Color(red: 0.0, green: 0.6, blue: 0.0)
        default:        return Color(white: 0.55)
        }
    }
    
    var dividerColor: Color {
        return Color.white.opacity(0.08)
    }
    
    var cardColor: Color {
        switch self {
        case .default:  return Color(white: 0.1)
        case .classic:  return Color(red: 0.2, green: 0.2, blue: 0.25)
        case .matrix:   return Color(white: 0.06)
        case .sunset:   return Color(red: 0.14, green: 0.1, blue: 0.08)
        case .ocean:    return Color(red: 0.08, green: 0.1, blue: 0.16)
        }
    }
    
    var hoverColor: Color {
        return Color.white.opacity(0.04)
    }
    
    var glassEdgeColor: Color {
        return Color.white.opacity(0.12)
    }
    
    var surfaceMaterial: Material {
        return .ultraThinMaterial
    }
    
    var visualizerGradient: LinearGradient {
        return LinearGradient(colors: visualizerColors, startPoint: .bottom, endPoint: .top)
    }
    
    var visualizerColors: [Color] {
        switch self {
        case .default:  return [Color(red: 0.49, green: 0.11, blue: 0.8), accentColor]
        case .classic:  return [Color(red: 0.4, green: 0.3, blue: 0.6), accentColor]
        case .matrix:   return [Color(red: 0.0, green: 0.2, blue: 0.0), accentColor]
        case .sunset:   return [Color(red: 0.6, green: 0.15, blue: 0.0), accentColor]
        case .ocean:    return [Color(red: 0.0, green: 0.15, blue: 0.35), accentColor]
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("AppThemePreference") private var savedThemeRawValue: String = AppTheme.default.rawValue
    
    @Published var currentTheme: AppTheme = .default {
        didSet {
            savedThemeRawValue = currentTheme.rawValue
        }
    }
    
    private init() {
        if let saved = AppTheme(rawValue: savedThemeRawValue) {
            currentTheme = saved
        }
    }
}
