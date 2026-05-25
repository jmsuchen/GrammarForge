import Foundation

enum SkillStatus: String, CaseIterable, Identifiable {
    case locked = "未解锁"
    case available = "可训练"
    case training = "训练中"
    case basic = "基本掌握"
    case proficient = "熟练掌握"
    case review = "需要复习"

    var id: String { rawValue }
}

struct GrammarSkill: Identifiable, Hashable {
    let id: UUID
    let module: String
    let name: String
    let description: String
    let difficulty: Int
    var mastery: Double
    var totalAttempts: Int
    var correctAttempts: Int
    var repeatErrorCount: Int
    var recentResults: [Bool]
    var status: SkillStatus

    var accuracy: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctAttempts) / Double(totalAttempts)
    }
}

struct Exercise: Identifiable, Hashable {
    let id: UUID
    let skillID: UUID
    let chineseSentence: String
    let referenceAnswer: String
    let difficulty: Int
}

struct GradingResult: Identifiable, Hashable {
    let id = UUID()
    let isCorrect: Bool
    let score: Int
    let correctedSentence: String
    let errorTypes: [String]
    let explanationCN: String
    let betterVersion: String
    let similarQuestionCN: String
}

struct Submission: Identifiable, Hashable {
    let id: UUID
    let exercise: Exercise
    let skillName: String
    let userAnswer: String
    let result: GradingResult
    let createdAt: Date
}

struct SkillRecommendation: Identifiable {
    let id = UUID()
    let skill: GrammarSkill
    let reason: String
}
