import SwiftUI
import UIKit

enum MomentumTheme {
    static let pulse = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.35, blue: 0.62, alpha: 1)
            : UIColor(red: 0.82, green: 0.10, blue: 0.43, alpha: 1)
    })
    static let pulseDarkAppearance = Color(red: 0.96, green: 0.35, blue: 0.62)
    static let pulseDeep = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.76, green: 0.14, blue: 0.36, alpha: 1)
            : UIColor(red: 0.55, green: 0.05, blue: 0.22, alpha: 1)
    })
    static let pulseWash = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.08, blue: 0.15, alpha: 1)
            : UIColor(red: 1.00, green: 0.91, blue: 0.94, alpha: 1)
    })
    static let dataCyan = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.78, blue: 0.84, alpha: 1)
            : UIColor(red: 0.10, green: 0.56, blue: 0.65, alpha: 1)
    })
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
}

enum MomentumSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
