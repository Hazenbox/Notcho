import Foundation
import NaturalLanguage
import os.log

actor TopicExtractor {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "TopicExtractor")
    
    private let tagger: NLTagger
    
    init() {
        tagger = NLTagger(tagSchemes: [.lexicalClass])
    }
    
    func extractTopic(from text: String) -> String? {
        tagger.string = text
        
        var nounCounts: [String: Int] = [:]
        let range = text.startIndex..<text.endIndex
        
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            guard let tag = tag else { return true }
            
            if tag == .noun || tag == .verb {
                let word = String(text[tokenRange]).lowercased()
                
                if word.count >= 3 && !isCommonWord(word) {
                    nounCounts[word, default: 0] += 1
                }
            }
            return true
        }
        
        guard !nounCounts.isEmpty else { return nil }
        
        let sortedNouns = nounCounts.sorted { $0.value > $1.value }
        
        let topNouns = sortedNouns.prefix(3).map { $0.key.capitalized }
        
        if topNouns.isEmpty {
            return nil
        } else if topNouns.count == 1 {
            return topNouns[0]
        } else {
            return topNouns.joined(separator: " / ")
        }
    }
    
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords = Set([
            "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
            "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
            "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
            "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
            "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
            "when", "make", "can", "like", "time", "no", "just", "him", "know", "take",
            "people", "into", "year", "your", "good", "some", "could", "them", "see", "other",
            "than", "then", "now", "look", "only", "come", "its", "over", "think", "also",
            "back", "after", "use", "two", "how", "our", "work", "first", "well", "way",
            "even", "new", "want", "because", "any", "these", "give", "day", "most", "us",
            "yeah", "okay", "um", "uh", "like", "right", "think", "going", "want", "know"
        ])
        return commonWords.contains(word)
    }
}
