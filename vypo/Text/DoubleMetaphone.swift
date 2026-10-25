import Foundation

/// Lawrence Philips' Double Metaphone, primary code only, max length 6 (§11.4).
///
/// A Swift translation of `org.apache.commons.codec.language.DoubleMetaphone` (Apache Commons Codec,
/// Copyright 2002-2026 The Apache Software Foundation, Apache License 2.0; see THIRD_PARTY_NOTICES.md).
/// Changed: translated from Java; only the primary code is kept, with a maximum length of 6 (the alternate
/// code, `setMaxCodeLen` and the encoder interfaces are dropped).
struct DoubleMetaphone {
    static let maxLength = 6

    static func primary(_ input: String) -> String {
        var m = DoubleMetaphone(input)
        return m.encode()
    }

    private let v: [Character]
    private let slavoGermanic: Bool
    private var result = ""

    private init(_ input: String) {
        v = Array(input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines))
        let s = String(v)
        slavoGermanic = s.contains("W") || s.contains("K") || s.contains("CZ") || s.contains("WITZ")
    }

    private mutating func encode() -> String {
        guard !v.isEmpty else { return "" }
        var i = 0
        if contains(0, 2, "GN", "KN", "PN", "WR", "PS") { i = 1 }
        while result.count < Self.maxLength && i < v.count {
            switch v[i] {
            case "A", "E", "I", "O", "U", "Y":
                if i == 0 { add("A") }
                i += 1
            case "B":
                add("P"); i = at(i + 1) == "B" ? i + 2 : i + 1
            case "Ç":
                add("S"); i += 1
            case "C":
                i = handleC(i)
            case "D":
                i = handleD(i)
            case "F":
                add("F"); i = at(i + 1) == "F" ? i + 2 : i + 1
            case "G":
                i = handleG(i)
            case "H":
                i = handleH(i)
            case "J":
                i = handleJ(i)
            case "K":
                add("K"); i = at(i + 1) == "K" ? i + 2 : i + 1
            case "L":
                add("L"); i = at(i + 1) == "L" ? i + 2 : i + 1
            case "M":
                add("M"); i = conditionM0(i) ? i + 2 : i + 1
            case "N":
                add("N"); i = at(i + 1) == "N" ? i + 2 : i + 1
            case "Ñ":
                add("N"); i += 1
            case "P":
                if at(i + 1) == "H" { add("F"); i += 2 } else {
                    add("P"); i = contains(i + 1, 1, "P", "B") ? i + 2 : i + 1
                }
            case "Q":
                add("K"); i = at(i + 1) == "Q" ? i + 2 : i + 1
            case "R":
                i = handleR(i)
            case "S":
                i = handleS(i)
            case "T":
                i = handleT(i)
            case "V":
                add("F"); i = at(i + 1) == "V" ? i + 2 : i + 1
            case "W":
                i = handleW(i)
            case "X":
                i = handleX(i)
            case "Z":
                i = handleZ(i)
            default:
                i += 1
            }
        }
        return String(result.prefix(Self.maxLength))
    }

    // MARK: Helpers

    private mutating func add(_ s: String) { result += s }

    private func at(_ i: Int) -> Character { i >= 0 && i < v.count ? v[i] : "\0" }

    private func isVowel(_ c: Character) -> Bool { "AEIOUY".contains(c) }

    private func contains(_ start: Int, _ length: Int, _ options: String...) -> Bool {
        guard start >= 0, start + length <= v.count else { return false }
        let sub = String(v[start..<(start + length)])
        return options.contains(sub)
    }

    // MARK: Letters

    private func conditionC0(_ i: Int) -> Bool {
        if contains(i, 4, "CHIA") { return true }
        if i <= 1 { return false }
        if isVowel(at(i - 2)) { return false }
        if !contains(i - 1, 3, "ACH") { return false }
        let c = at(i + 2)
        return (c != "I" && c != "E") || contains(i - 2, 6, "BACHER", "MACHER")
    }

    private func conditionCH0(_ i: Int) -> Bool {
        guard i == 0 else { return false }
        if !contains(i + 1, 5, "HARAC", "HARIS") && !contains(i + 1, 3, "HOR", "HYM", "HIA", "HEM") { return false }
        return !contains(0, 5, "CHORE")
    }

    private func conditionCH1(_ i: Int) -> Bool {
        contains(0, 4, "VAN ", "VON ") || contains(0, 3, "SCH")
            || contains(i - 2, 6, "ORCHES", "ARCHIT", "ORCHID")
            || contains(i + 2, 1, "T", "S")
            || ((contains(i - 1, 1, "A", "O", "U", "E") || i == 0)
                && (contains(i + 2, 1, "L", "R", "N", "M", "B", "H", "F", "V", "W", " ") || i + 1 == v.count - 1))
    }

    private func conditionM0(_ i: Int) -> Bool {
        if at(i + 1) == "M" { return true }
        return contains(i - 1, 3, "UMB") && (i + 1 == v.count - 1 || contains(i + 2, 2, "ER"))
    }

    private mutating func handleC(_ i: Int) -> Int {
        if conditionC0(i) { add("K"); return i + 2 }
        if i == 0 && contains(i, 6, "CAESAR") { add("S"); return i + 2 }
        if contains(i, 2, "CH") { return handleCH(i) }
        if contains(i, 2, "CZ") && !contains(i - 2, 4, "WICZ") { add("S"); return i + 2 }
        if contains(i + 1, 3, "CIA") { add("X"); return i + 3 }
        if contains(i, 2, "CC") && !(i == 1 && at(0) == "M") { return handleCC(i) }
        if contains(i, 2, "CK", "CG", "CQ") { add("K"); return i + 2 }
        if contains(i, 2, "CI", "CE", "CY") { add("S"); return i + 2 }
        add("K")
        if contains(i + 1, 2, " C", " Q", " G") { return i + 3 }
        if contains(i + 1, 1, "C", "K", "Q") && !contains(i + 1, 2, "CE", "CI") { return i + 2 }
        return i + 1
    }

    private mutating func handleCC(_ i: Int) -> Int {
        if contains(i + 2, 1, "I", "E", "H") && !contains(i + 2, 2, "HU") {
            if (i == 1 && at(i - 1) == "A") || contains(i - 1, 5, "UCCEE", "UCCES") { add("KS") } else { add("X") }
            return i + 3
        }
        add("K")
        return i + 2
    }

    private mutating func handleCH(_ i: Int) -> Int {
        if i > 0 && contains(i, 4, "CHAE") { add("K"); return i + 2 }
        if conditionCH0(i) || conditionCH1(i) { add("K"); return i + 2 }
        if i > 0 { add(contains(0, 2, "MC") ? "K" : "X") } else { add("X") }
        return i + 2
    }

    private mutating func handleD(_ i: Int) -> Int {
        if contains(i, 2, "DG") {
            if contains(i + 2, 1, "I", "E", "Y") { add("J"); return i + 3 }
            add("TK"); return i + 2
        }
        if contains(i, 2, "DT", "DD") { add("T"); return i + 2 }
        add("T")
        return i + 1
    }

    private mutating func handleG(_ i: Int) -> Int {
        if at(i + 1) == "H" { return handleGH(i) }
        if at(i + 1) == "N" {
            if i == 1 && isVowel(at(0)) && !slavoGermanic { add("KN") }
            else if !contains(i + 2, 2, "EY") && at(i + 1) != "Y" && !slavoGermanic { add("N") }
            else { add("KN") }
            return i + 2
        }
        if contains(i + 1, 2, "LI") && !slavoGermanic { add("KL"); return i + 2 }
        if i == 0 && (at(i + 1) == "Y" || contains(i + 1, 2, "ES", "EP", "EB", "EL", "EY", "IB", "IL", "IN", "IE", "EI", "ER")) {
            add("K"); return i + 2
        }
        if (contains(i + 1, 2, "ER") || at(i + 1) == "Y") && !contains(0, 6, "DANGER", "RANGER", "MANGER")
            && !contains(i - 1, 1, "E", "I") && !contains(i - 1, 3, "RGY", "OGY") {
            add("K"); return i + 2
        }
        if contains(i + 1, 1, "E", "I", "Y") || contains(i - 1, 4, "AGGI", "OGGI") {
            if contains(0, 4, "VAN ", "VON ") || contains(0, 3, "SCH") || contains(i + 1, 2, "ET") { add("K") }
            else { add("J") }
            return i + 2
        }
        add("K")
        return at(i + 1) == "G" ? i + 2 : i + 1
    }

    private mutating func handleGH(_ i: Int) -> Int {
        if i > 0 && !isVowel(at(i - 1)) { add("K"); return i + 2 }
        if i == 0 { add(at(i + 2) == "I" ? "J" : "K"); return i + 2 }
        if (i > 1 && contains(i - 2, 1, "B", "H", "D")) || (i > 2 && contains(i - 3, 1, "B", "H", "D"))
            || (i > 3 && contains(i - 4, 1, "B", "H")) {
            return i + 2
        }
        if i > 2 && at(i - 1) == "U" && contains(i - 3, 1, "C", "G", "L", "R", "T") { add("F") }
        else if i > 0 && at(i - 1) != "I" { add("K") }
        return i + 2
    }

    private mutating func handleH(_ i: Int) -> Int {
        if (i == 0 || isVowel(at(i - 1))) && isVowel(at(i + 1)) { add("H"); return i + 2 }
        return i + 1
    }

    private mutating func handleJ(_ i: Int) -> Int {
        if contains(i, 4, "JOSE") || contains(0, 4, "SAN ") {
            if (i == 0 && at(i + 4) == " ") || v.count == 4 || contains(0, 4, "SAN ") { add("H") } else { add("J") }
            return i + 1
        }
        if i == 0 && !contains(i, 4, "JOSE") { add("J") }
        else if isVowel(at(i - 1)) && !slavoGermanic && (at(i + 1) == "A" || at(i + 1) == "O") { add("J") }
        else if i == v.count - 1 { add("J") }
        else if !contains(i + 1, 1, "L", "T", "K", "S", "N", "M", "B", "Z") && !contains(i - 1, 1, "S", "K", "L") { add("J") }
        return at(i + 1) == "J" ? i + 2 : i + 1
    }

    private mutating func handleR(_ i: Int) -> Int {
        let silent = i == v.count - 1 && !slavoGermanic && contains(i - 2, 2, "IE") && !contains(i - 4, 2, "ME", "MA")
        if !silent { add("R") }
        return at(i + 1) == "R" ? i + 2 : i + 1
    }

    private mutating func handleS(_ i: Int) -> Int {
        if contains(i - 1, 3, "ISL", "YSL") { return i + 1 }
        if i == 0 && contains(i, 5, "SUGAR") { add("X"); return i + 1 }
        if contains(i, 2, "SH") {
            add(contains(i + 1, 4, "HEIM", "HOEK", "HOLM", "HOLZ") ? "S" : "X")
            return i + 2
        }
        if contains(i, 3, "SIO", "SIA") || contains(i, 4, "SIAN") { add("S"); return i + 3 }
        if (i == 0 && contains(i + 1, 1, "M", "N", "L", "W")) || contains(i + 1, 1, "Z") {
            add("S")
            return contains(i + 1, 1, "Z") ? i + 2 : i + 1
        }
        if contains(i, 2, "SC") { return handleSC(i) }
        if !(i == v.count - 1 && contains(i - 2, 2, "AI", "OI")) { add("S") }
        return contains(i + 1, 1, "S", "Z") ? i + 2 : i + 1
    }

    private mutating func handleSC(_ i: Int) -> Int {
        if at(i + 2) == "H" {
            if contains(i + 3, 2, "OO", "ER", "EN", "UY", "ED", "EM") {
                add(contains(i + 3, 2, "ER", "EN") ? "X" : "SK")
            } else {
                add("X")
            }
        } else if contains(i + 2, 1, "I", "E", "Y") {
            add("S")
        } else {
            add("SK")
        }
        return i + 3
    }

    private mutating func handleT(_ i: Int) -> Int {
        if contains(i, 4, "TION") { add("X"); return i + 3 }
        if contains(i, 3, "TIA", "TCH") { add("X"); return i + 3 }
        if contains(i, 2, "TH") || contains(i, 3, "TTH") {
            if contains(i + 2, 2, "OM", "AM") || contains(0, 4, "VAN ", "VON ") || contains(0, 3, "SCH") { add("T") } else { add("0") }
            return i + 2
        }
        add("T")
        return contains(i + 1, 1, "T", "D") ? i + 2 : i + 1
    }

    private mutating func handleW(_ i: Int) -> Int {
        if contains(i, 2, "WR") { add("R"); return i + 2 }
        if i == 0 && (isVowel(at(i + 1)) || contains(i, 2, "WH")) { add("A"); return i + 1 }
        if (i == v.count - 1 && isVowel(at(i - 1))) || contains(i - 1, 5, "EWSKI", "EWSKY", "OWSKI", "OWSKY") || contains(0, 3, "SCH") {
            return i + 1
        }
        if contains(i, 4, "WICZ", "WITZ") { add("TS"); return i + 4 }
        return i + 1
    }

    private mutating func handleX(_ i: Int) -> Int {
        if i == 0 { add("S"); return i + 1 }
        if !(i == v.count - 1 && (contains(i - 3, 3, "IAU", "EAU") || contains(i - 2, 2, "AU", "OU"))) { add("KS") }
        return contains(i + 1, 1, "C", "X") ? i + 2 : i + 1
    }

    private mutating func handleZ(_ i: Int) -> Int {
        if at(i + 1) == "H" { add("J"); return i + 2 }
        add("S")
        return at(i + 1) == "Z" ? i + 2 : i + 1
    }
}
