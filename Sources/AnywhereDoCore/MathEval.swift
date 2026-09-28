import Foundation

/// 一个极小的递归下降计算器：+ - * / % ^ 括号，支持 × ÷ 与 "2 x 3" 写法。
public enum MathEval {
    public static func evaluate(_ input: String) -> Double? {
        var parser = Parser(tokens: tokenize(normalize(input)))
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// 判断一段文本是否“看起来像算式”，避免把普通句子送进计算器。
    public static func looksLikeExpression(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 120 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,+-*/%^() xX×÷")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let normalized = normalize(trimmed)
        let operators = normalized.filter { "+-*/%^".contains($0) }
        guard !operators.isEmpty else { return false }
        // 至少要有两个数字，排除 "+-" 这类噪声。
        let digits = normalized.filter { $0.isNumber }
        return digits.count >= 2
    }

    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - 词法

    private struct Parser {
        let tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index >= tokens.count }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let token = peek(), case .op = token {
                switch token {
                case .op(let symbol):
                    if symbol == "+" || symbol == "-" {
                        index += 1
                        guard let rhs = parseTerm() else { return nil }
                        value = symbol == "+" ? value + rhs : value - rhs
                        continue
                    }
                    return value
                default:
                    return value
                }
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let token = peek(), case .op(let symbol) = token,
                  symbol == "*" || symbol == "/" || symbol == "%" {
                index += 1
                guard let rhs = parseUnary() else { return nil }
                switch symbol {
                case "*": value *= rhs
                case "/": value /= rhs
                default:
                    if rhs == 0 { return nil }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        private mutating func parseUnary() -> Double? {
            if let token = peek(), case .op(let symbol) = token, symbol == "-" || symbol == "+" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return symbol == "-" ? -value : value
            }
            return parsePower()
        }

        private mutating func parsePower() -> Double? {
            guard let base = parsePrimary() else { return nil }
            if let token = peek(), case .op(let symbol) = token, symbol == "^" {
                index += 1
                guard let exponent = parseUnary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        private mutating func parsePrimary() -> Double? {
            guard let token = peek() else { return nil }
            switch token {
            case .number(let value):
                index += 1
                return value
            case .op("("):
                index += 1
                guard let value = parseExpression() else { return nil }
                guard let closing = peek(), case .op(")") = closing else { return nil }
                index += 1
                return value
            default:
                return nil
            }
        }

        private func peek() -> Token? {
            index < tokens.count ? tokens[index] : nil
        }
    }

    private enum Token: Equatable {
        case number(Double)
        case op(String)
    }

    private static func normalize(_ input: String) -> String {
        var output = ""
        let characters = Array(input)
        /// 跳过空白向两侧找数字，用于识别 "2 x 3" 里的乘号。
        func neighborIsDigit(from index: Int, step: Int) -> Bool {
            var cursor = index + step
            while cursor >= 0 && cursor < characters.count && characters[cursor].isWhitespace {
                cursor += step
            }
            guard cursor >= 0, cursor < characters.count else { return false }
            return characters[cursor].isNumber
        }
        for (index, character) in characters.enumerated() {
            switch character {
            case "×", "✕", "✖":
                output.append("*")
            case "÷":
                output.append("/")
            case "x", "X":
                // 只在 "2x3" / "2 x 3" 这种两侧是数字的场景当作乘号。
                if neighborIsDigit(from: index, step: -1), neighborIsDigit(from: index, step: 1) {
                    output.append("*")
                } else {
                    output.append(character)
                }
            case ",":
                // 千分位逗号直接丢弃（"1,000 + 2"）。
                continue
            default:
                output.append(character)
            }
        }
        return output
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var numberBuffer = ""
        func flush() {
            if !numberBuffer.isEmpty, let value = Double(numberBuffer) {
                tokens.append(.number(value))
            }
            numberBuffer = ""
        }
        for character in input {
            if character.isNumber || character == "." {
                numberBuffer.append(character)
            } else if "+-*/%^()".contains(character) {
                flush()
                tokens.append(.op(String(character)))
            } else if character.isWhitespace {
                flush()
            } else {
                return []
            }
        }
        flush()
        return tokens
    }
}
