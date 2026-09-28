import Foundation

public struct RGBAColor: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        if alpha >= 0.999 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, Int((alpha * 255).rounded()))
    }

    public var rgbString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        if alpha >= 0.999 {
            return "rgb(\(r), \(g), \(b))"
        }
        return "rgba(\(r), \(g), \(b), \(trimmed(alpha)))"
    }

    /// 给 Swift / SwiftUI 开发者直接用的字面量。
    public var swiftLiteral: String {
        "Color(red: \(trimmed(red)), green: \(trimmed(green)), blue: \(trimmed(blue)))"
    }

    public var hsbString: String {
        var hue = 0.0
        var saturation = 0.0
        var brightness = 0.0
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        brightness = maxValue
        saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
        if maxValue != minValue {
            let delta = maxValue - minValue
            if maxValue == red {
                hue = (green - blue) / delta + (green < blue ? 6 : 0)
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
        }
        return String(format: "HSB %.0f°, %.0f%%, %.0f%%", hue * 360, saturation * 100, brightness * 100)
    }

    private func trimmed(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(rounded)
    }
}

public enum ColorTools {
    /// 支持 #RGB / #RGBA / #RRGGBB / #RRGGBBAA / 0xRRGGBB / rgb() / rgba()。
    public static func parse(_ input: String) -> RGBAColor? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.count <= 40 else { return nil }

        if text.hasPrefix("rgba(") || text.hasPrefix("rgb(") {
            let inner = text
                .replacingOccurrences(of: "rgba(", with: "")
                .replacingOccurrences(of: "rgb(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let parts = inner
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3 || parts.count == 4 else { return nil }
            var values: [Double] = []
            for part in parts {
                if part.hasSuffix("%") {
                    guard let value = Double(part.dropLast()) else { return nil }
                    values.append(value / 100)
                } else {
                    guard let value = Double(part) else { return nil }
                    values.append(value / 255)
                }
            }
            guard values.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return nil }
            return RGBAColor(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
        }

        if text.hasPrefix("0x") { text = "#" + text.dropFirst(2) }
        guard text.hasPrefix("#") else { return nil }
        let hex = String(text.dropFirst())
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        func component(_ slice: Substring) -> Double {
            Double(Int(slice, radix: 16) ?? 0) / 255
        }

        switch hex.count {
        case 3, 4:
            let chars = Array(hex)
            let expanded = chars.map { "\($0)\($0)" }.joined()
            return parse("#" + expanded)
        case 6:
            return RGBAColor(
                red: component(hex.prefix(2)),
                green: component(hex.dropFirst(2).prefix(2)),
                blue: component(hex.dropFirst(4).prefix(2))
            )
        case 8:
            return RGBAColor(
                red: component(hex.prefix(2)),
                green: component(hex.dropFirst(2).prefix(2)),
                blue: component(hex.dropFirst(4).prefix(2)),
                alpha: component(hex.dropFirst(6).prefix(2))
            )
        default:
            return nil
        }
    }
}
