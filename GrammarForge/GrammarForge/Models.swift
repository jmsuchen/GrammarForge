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

enum VocabularyLevel: String, CaseIterable, Identifiable {
    case middleSchool = "初中"
    case highSchool = "高中"
    case cet4 = "四级"
    case cet6 = "六级"
    case ielts = "雅思"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .middleSchool:
            return "初中核心词汇，句子尽量简洁"
        case .highSchool:
            return "高中常用词汇，表达自然但不过度复杂"
        case .cet4:
            return "大学英语四级词汇，适合基础大学英语输出"
        case .cet6:
            return "大学英语六级词汇，允许更精准的抽象表达"
        case .ielts:
            return "雅思写作/口语常用词汇，表达更地道但不要堆砌生词"
        }
    }
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
