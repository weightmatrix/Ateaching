import Foundation

enum NodeMarkdownFormulaLatexNormalizer {
    static func normalize(_ latex: String) -> String {
        let punctuationNormalized = latex
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "【", with: "[")
            .replacingOccurrences(of: "】", with: "]")
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "＝", with: "=")
            .replacingOccurrences(of: "＜", with: "<")
            .replacingOccurrences(of: "＞", with: ">")
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "×", with: "\\times ")
            .replacingOccurrences(of: "÷", with: "\\div ")
            .replacingOccurrences(of: "……", with: "\\cdots ")
            .replacingOccurrences(of: "···", with: "\\cdots ")
            .replacingOccurrences(of: "、", with: ",")
        let symbolNormalized = replaceUnicodeMathSymbols(in: punctuationNormalized)
        // Script ownership must be resolved before general CJK wrapping. Otherwise
        // `X_后 - X_前` can be mistaken for one long text subscript and shrink the
        // second variable together with the real subscript.
        let scriptNormalized = wrapCJKScriptGroups(in: symbolNormalized)
        let radicalNormalized = wrapSqrtTextRadicands(in: scriptNormalized)
        return wrapStandaloneCJKGroups(in: radicalNormalized)
    }

    private static func replaceUnicodeMathSymbols(in latex: String) -> String {
        var output = String()
        output.reserveCapacity(latex.count)
        var isEscapedCommand = false
        for character in latex {
            if character == "\\" {
                isEscapedCommand = true
                output.append(character)
                continue
            }
            if isEscapedCommand {
                output.append(character)
                isEscapedCommand = character.isLetter
                continue
            }
            if let replacement = unicodeMathSymbolMap[character] {
                output.append(replacement)
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func wrapCJKScriptGroups(in latex: String) -> String {
        var output = String()
        var index = latex.startIndex
        while index < latex.endIndex {
            let character = latex[index]
            guard (character == "_" || character == "^"),
                  let next = latex.index(index, offsetBy: 1, limitedBy: latex.endIndex) else {
                output.append(character)
                index = latex.index(after: index)
                continue
            }

            if next < latex.endIndex, latex[next] == "{" {
                guard let close = matchingBraceIndex(in: latex, openingBrace: next) else {
                    output.append(character)
                    index = latex.index(after: index)
                    continue
                }
                let contentStart = latex.index(after: next)
                let content = String(latex[contentStart..<close])
                output.append(character)
                if shouldWrapAsText(content) {
                    output.append("{\\text{")
                    output.append(content)
                    output.append("}}")
                } else {
                    output.append(String(latex[next...close]))
                }
                index = latex.index(after: close)
                continue
            }

            if next < latex.endIndex, containsCJK(latex[next]) {
                output.append(character)
                output.append("{\\text{")
                output.append(latex[next])
                output.append("}}")
                index = latex.index(after: next)
                continue
            }

            output.append(character)
            index = latex.index(after: index)
        }
        return output
    }

    private static func wrapStandaloneCJKGroups(in latex: String) -> String {
        var output = String()
        var index = latex.startIndex
        while index < latex.endIndex {
            if latex[index] == "\\" {
                let commandStart = index
                var command = "\\"
                output.append(latex[index])
                index = latex.index(after: index)
                while index < latex.endIndex, latex[index].isLetter {
                    command.append(latex[index])
                    output.append(latex[index])
                    index = latex.index(after: index)
                }
                if command == "\\text",
                   index < latex.endIndex,
                   latex[index] == "{",
                   let close = matchingBraceIndex(in: latex, openingBrace: index) {
                    output.append(String(latex[index...close]))
                    index = latex.index(after: close)
                    continue
                }
                if commandStart != index {
                    continue
                }
            }

            guard containsCJK(latex[index]) else {
                output.append(latex[index])
                index = latex.index(after: index)
                continue
            }

            let groupStart = index
            while index < latex.endIndex, shouldJoinTextRunCharacter(latex[index]) {
                index = latex.index(after: index)
            }
            let group = String(latex[groupStart..<index])
            output.append("\\text{")
            output.append(group)
            output.append("}")
        }
        return output
    }

    private static func shouldJoinTextRunCharacter(_ character: Character) -> Bool {
        containsCJK(character)
            || character.isNumber
            || character.isLetter
    }

    private static func wrapSqrtTextRadicands(in latex: String) -> String {
        var output = String()
        var index = latex.startIndex
        while index < latex.endIndex {
            guard latex[index] == "\\",
                  latex[index...].hasPrefix("\\sqrt") else {
                output.append(latex[index])
                index = latex.index(after: index)
                continue
            }

            let commandStart = index
            var cursor = latex.index(commandStart, offsetBy: "\\sqrt".count)
            var optionalArgument = ""
            if cursor < latex.endIndex, latex[cursor] == "[" {
                guard let optionalClose = matchingBracketIndex(in: latex, openingBracket: cursor) else {
                    output.append(latex[index])
                    index = latex.index(after: index)
                    continue
                }
                optionalArgument = String(latex[cursor...optionalClose])
                cursor = latex.index(after: optionalClose)
            }

            guard cursor < latex.endIndex, latex[cursor] == "{",
                  let radicandClose = matchingBraceIndex(in: latex, openingBrace: cursor) else {
                output.append(String(latex[commandStart..<cursor]))
                index = cursor
                continue
            }

            let radicandStart = latex.index(after: cursor)
            let radicand = String(latex[radicandStart..<radicandClose])
            output.append("\\sqrt")
            output.append(optionalArgument)
            if shouldWrapAsText(radicand) {
                output.append("{\\text{")
                output.append(radicand)
                output.append("}}")
            } else {
                output.append(String(latex[cursor...radicandClose]))
            }
            index = latex.index(after: radicandClose)
        }
        return output
    }

    private static func matchingBracketIndex(in latex: String, openingBracket: String.Index) -> String.Index? {
        var depth = 0
        var index = openingBracket
        while index < latex.endIndex {
            let character = latex[index]
            if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = latex.index(after: index)
        }
        return nil
    }

    private static func matchingBraceIndex(in latex: String, openingBrace: String.Index) -> String.Index? {
        var depth = 0
        var index = openingBrace
        while index < latex.endIndex {
            let character = latex[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = latex.index(after: index)
        }
        return nil
    }

    private static func shouldWrapAsText(_ content: String) -> Bool {
        guard content.contains(where: { containsCJK($0) }) else { return false }
        return !content.contains("\\")
    }

    private static func containsCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF,
                 0x3000...0x303F,
                 0x3040...0x30FF,
                 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private static let unicodeMathSymbolMap: [Character: String] = [
        "α": "\\alpha ",
        "β": "\\beta ",
        "γ": "\\gamma ",
        "δ": "\\delta ",
        "ε": "\\epsilon ",
        "ζ": "\\zeta ",
        "η": "\\eta ",
        "θ": "\\theta ",
        "ι": "\\iota ",
        "κ": "\\kappa ",
        "λ": "\\lambda ",
        "μ": "\\mu ",
        "ν": "\\nu ",
        "ξ": "\\xi ",
        "ο": "\\mathrm{o}",
        "π": "\\pi ",
        "ρ": "\\rho ",
        "σ": "\\sigma ",
        "ς": "\\varsigma ",
        "τ": "\\tau ",
        "υ": "\\upsilon ",
        "φ": "\\phi ",
        "χ": "\\chi ",
        "ψ": "\\psi ",
        "ω": "\\omega ",
        "Α": "\\mathrm{A}",
        "Β": "\\mathrm{B}",
        "Γ": "\\Gamma ",
        "Δ": "\\Delta ",
        "∆": "\\Delta ",
        "Ε": "\\mathrm{E}",
        "Ζ": "\\mathrm{Z}",
        "Η": "\\mathrm{H}",
        "Θ": "\\Theta ",
        "Ι": "\\mathrm{I}",
        "Κ": "\\mathrm{K}",
        "Λ": "\\Lambda ",
        "Μ": "\\mathrm{M}",
        "Ν": "\\mathrm{N}",
        "Ξ": "\\Xi ",
        "Ο": "\\mathrm{O}",
        "Π": "\\Pi ",
        "Ρ": "\\mathrm{P}",
        "Σ": "\\Sigma ",
        "Τ": "\\mathrm{T}",
        "Υ": "\\Upsilon ",
        "Φ": "\\Phi ",
        "Χ": "\\mathrm{X}",
        "Ψ": "\\Psi ",
        "Ω": "\\Omega ",
        "ϐ": "\\beta ",
        "ϑ": "\\vartheta ",
        "ϕ": "\\varphi ",
        "ϖ": "\\varpi ",
        "ϱ": "\\varrho ",
        "ϵ": "\\varepsilon ",
        "ϰ": "\\varkappa ",
        "µ": "\\mu ",
        "⍵": "\\omega ",
        "ℏ": "\\hbar ",
        "ℓ": "\\ell ",
        "℘": "\\wp ",
        "ℑ": "\\Im ",
        "ℜ": "\\Re ",
        "ℵ": "\\aleph ",
        "ℕ": "\\mathbb{N}",
        "ℤ": "\\mathbb{Z}",
        "ℚ": "\\mathbb{Q}",
        "ℝ": "\\mathbb{R}",
        "ℂ": "\\mathbb{C}",
        "≤": "\\leq ",
        "≥": "\\geq ",
        "≦": "\\leq ",
        "≧": "\\geq ",
        "≠": "\\neq ",
        "≈": "\\approx ",
        "≃": "\\simeq ",
        "≅": "\\cong ",
        "≌": "\\cong ",
        "≒": "\\fallingdotseq ",
        "≪": "\\ll ",
        "≫": "\\gg ",
        "≡": "\\equiv ",
        "≢": "\\not\\equiv ",
        "∼": "\\sim ",
        "∝": "\\propto ",
        "∧": "\\wedge ",
        "∨": "\\vee ",
        "∩": "\\cap ",
        "∪": "\\cup ",
        "∴": "\\therefore ",
        "∵": "\\because ",
        "±": "\\pm ",
        "∓": "\\mp ",
        "∞": "\\infty ",
        "∂": "\\partial ",
        "∇": "\\nabla ",
        "√": "\\sqrt{}",
        "∫": "\\int ",
        "∮": "\\oint ",
        "∬": "\\iint ",
        "∭": "\\iiint ",
        "∑": "\\sum ",
        "∏": "\\prod ",
        "∈": "\\in ",
        "∉": "\\notin ",
        "∋": "\\ni ",
        "⊂": "\\subset ",
        "⊃": "\\supset ",
        "⊆": "\\subseteq ",
        "⊇": "\\supseteq ",
        "∅": "\\emptyset ",
        "∀": "\\forall ",
        "∃": "\\exists ",
        "¬": "\\neg ",
        "⇒": "\\Rightarrow ",
        "⇐": "\\Leftarrow ",
        "⇔": "\\Leftrightarrow ",
        "↦": "\\mapsto ",
        "↗": "\\nearrow ",
        "↘": "\\searrow ",
        "↙": "\\swarrow ",
        "↖": "\\nwarrow ",
        "→": "\\to ",
        "←": "\\leftarrow ",
        "↔": "\\leftrightarrow ",
        "↑": "\\uparrow ",
        "↓": "\\downarrow ",
        "∥": "\\parallel ",
        "⊥": "\\perp ",
        "∠": "\\angle ",
        "∟": "\\angle ",
        "△": "\\triangle ",
        "▽": "\\triangledown ",
        "□": "\\square ",
        "◇": "\\diamond ",
        "·": "\\cdot ",
        "⋅": "\\cdot ",
        "⋯": "\\cdots ",
        "…": "\\cdots ",
        "∗": "\\ast ",
        "°": "^{\\circ}",
        "′": "'",
        "″": "''",
        "①": "\\text{①}",
        "②": "\\text{②}",
        "③": "\\text{③}",
        "④": "\\text{④}",
        "⑤": "\\text{⑤}",
        "⑥": "\\text{⑥}",
        "⑦": "\\text{⑦}",
        "⑧": "\\text{⑧}",
        "⑨": "\\text{⑨}",
        "⑩": "\\text{⑩}",
        "⑪": "\\text{⑪}",
        "⑫": "\\text{⑫}",
        "⑬": "\\text{⑬}",
        "⑭": "\\text{⑭}",
        "⑮": "\\text{⑮}",
        "⑯": "\\text{⑯}",
        "⑰": "\\text{⑰}",
        "⑱": "\\text{⑱}",
        "⑲": "\\text{⑲}",
        "⑳": "\\text{⑳}"
    ]
}
