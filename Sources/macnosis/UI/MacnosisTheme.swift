import SwiftUI

enum MacnosisTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .textBackgroundColor)
    static let accent = Color(red: 0.18, green: 0.49, blue: 0.72)
    static let good = Color(red: 0.23, green: 0.56, blue: 0.42)
    static let warning = Color(red: 0.73, green: 0.34, blue: 0.27)
    static let debug = Color(red: 0.34, green: 0.43, blue: 0.58)
    static let neutral = Color(nsColor: .secondaryLabelColor)
    static let selection = Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
    static let border = Color(nsColor: .separatorColor)
    static let hover = Color.primary.opacity(0.06)
}
