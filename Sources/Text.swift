import Foundation

/// Uyg'otuvchi so'z ("Sherik") ni nutq aniqlagich matnidan topish.
enum WakeWord {
    private static let targets = ["sherik", "sharik", "serik", "cherik", "sherig", "sheriq", "sherick"]

    static func matches(_ text: String) -> Bool {
        let t = latinize(text.lowercased())
        let tokens = t.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for tok in tokens {
            for target in targets where abs(tok.count - target.count) <= 1 {
                if levenshtein(tok, target) <= 1 { return true }
            }
        }
        let joined = tokens.joined()
        return joined.contains("sherik") || joined.contains("sherrik") || joined.contains("sharik")
    }

    static func latinize(_ s: String) -> String {
        var x = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
        x = x.replacingOccurrences(of: "ı", with: "i")
        let map: [Character: String] = [
            "ш": "sh", "щ": "sh", "ч": "ch", "е": "e", "э": "e", "ё": "e", "р": "r", "и": "i",
            "й": "y", "к": "k", "қ": "q", "х": "x", "ў": "o", "ғ": "g", "ҳ": "h", "а": "a",
            "о": "o", "с": "s", "т": "t", "д": "d", "н": "n", "м": "m", "л": "l", "б": "b",
            "в": "v", "г": "g", "з": "z", "ж": "j", "у": "u", "ф": "f", "ц": "ts", "ь": "",
            "ъ": "", "ы": "i", "ю": "yu", "я": "ya",
        ]
        var out = ""
        for ch in x { out += map[ch] ?? String(ch) }
        return out
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[b.count]
    }
}

/// "Ha / Yo'q" javobini aniqlash.
enum YesNo {
    static func parse(_ text: String) -> Bool? {
        let t = WakeWord.latinize(text.lowercased())
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "ʻ", with: "")
            .replacingOccurrences(of: "’", with: "")
        let words = Set(t.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let no: Set<String> = ["yoq", "yok", "net", "nyet", "bekor", "kerakmas", "hechqisi", "yoqqa", "no", "yoqyoq", "kerakemas"]
        let yes: Set<String> = ["ha", "xa", "da", "xop", "hop", "mayli", "albatta", "ok", "okay", "yes", "boladi", "marhamat", "bajar", "ruxsat", "xo"]
        if !words.isDisjoint(with: no) || t.contains("kerak emas") { return false }
        if !words.isDisjoint(with: yes) { return true }
        return nil
    }
}

/// O'zbek lotin yozuvini turk imlosiga o'tkazish — o'zbekcha ovoz bo'lmaganda turkcha ovoz o'qishi uchun.
enum UzbekTranslit {
    static func toTurkish(_ s: String) -> String {
        var t = s.lowercased()
        for apo in ["ʻ", "ʼ", "’", "‘", "`", "´"] { t = t.replacingOccurrences(of: apo, with: "'") }
        t = t.replacingOccurrences(of: "o'", with: "o")
        t = t.replacingOccurrences(of: "g'", with: "ğ")
        t = t.replacingOccurrences(of: "sh", with: "ş")
        t = t.replacingOccurrences(of: "ch", with: "ç")
        t = t.replacingOccurrences(of: "j", with: "c")
        t = t.replacingOccurrences(of: "x", with: "h")
        t = t.replacingOccurrences(of: "q", with: "k")
        t = t.replacingOccurrences(of: "'", with: "")
        return t
    }

    /// Markdown va ortiqcha belgilarni olib tashlash (ovozga o'qish uchun).
    static func clean(_ s: String) -> String {
        var t = s
        for ch in ["*", "#", "`", "_", "[", "]"] { t = t.replacingOccurrences(of: ch, with: "") }
        t = t.replacingOccurrences(of: "\n", with: ". ")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
