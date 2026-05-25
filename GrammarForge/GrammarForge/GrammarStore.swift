import Foundation

@MainActor
final class GrammarStore: ObservableObject {
    @Published private(set) var skills: [GrammarSkill]
    @Published private(set) var exercises: [Exercise]
    @Published private(set) var submissions: [Submission] = []
    @Published var selectedSkillID: UUID?

    private let gradingService: AIGradingService

    init(gradingService: AIGradingService = BackendAIGradingService()) {
        let seed = GrammarSeed.make()
        self.skills = seed.skills
        self.exercises = seed.exercises
        self.selectedSkillID = seed.skills.first(where: { $0.status != .locked })?.id
        self.gradingService = gradingService
    }

    var currentStage: String {
        let average = skills.map(\.mastery).reduce(0, +) / Double(max(skills.count, 1))
        switch average {
        case 0..<45:
            return "基础输出阶段"
        case 45..<70:
            return "结构稳定阶段"
        default:
            return "表达升级阶段"
        }
    }

    var selectedSkill: GrammarSkill? {
        guard let selectedSkillID else { return nil }
        return skills.first { $0.id == selectedSkillID }
    }

    var currentExercise: Exercise? {
        guard let selectedSkillID else { return nil }
        return exercises.first { $0.skillID == selectedSkillID }
    }

    var recommendations: [SkillRecommendation] {
        skills
            .filter { $0.status != .locked }
            .sorted { recommendationScore(for: $0) > recommendationScore(for: $1) }
            .prefix(3)
            .map { skill in
                SkillRecommendation(
                    skill: skill,
                    reason: skill.mastery < 60 ? "掌握度偏低，适合继续输出训练。" : "近期仍有错误，适合做相似题巩固。"
                )
            }
    }

    var weakPoints: [String] {
        let recentErrors = submissions.flatMap { $0.result.errorTypes }
        if recentErrors.isEmpty {
            return ["时态准确性", "从句连接", "介词使用"]
        }
        return Array(Dictionary(grouping: recentErrors, by: { $0 })
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map(\.key))
    }

    var overallAccuracy: Double {
        guard !submissions.isEmpty else { return 0.74 }
        let correct = submissions.filter { $0.result.isCorrect }.count
        return Double(correct) / Double(submissions.count)
    }

    func select(_ skill: GrammarSkill) {
        selectedSkillID = skill.id
    }

    func submitCurrentAnswer(_ answer: String) async {
        guard let skill = selectedSkill, let exercise = currentExercise else { return }
        let result = await gradingService.grade(answer: answer, exercise: exercise, skill: skill)
        let submission = Submission(
            id: UUID(),
            exercise: exercise,
            skillName: skill.name,
            userAnswer: answer,
            result: result,
            createdAt: .now
        )
        submissions.insert(submission, at: 0)
        updateMastery(for: skill.id, wasCorrect: result.isCorrect)
        if !result.isCorrect {
            addSimilarExercise(from: result, skillID: skill.id)
        }
    }

    private func updateMastery(for skillID: UUID, wasCorrect: Bool) {
        guard let index = skills.firstIndex(where: { $0.id == skillID }) else { return }
        skills[index].totalAttempts += 1
        skills[index].correctAttempts += wasCorrect ? 1 : 0
        skills[index].repeatErrorCount += wasCorrect ? 0 : 1
        skills[index].recentResults.append(wasCorrect)
        skills[index].recentResults = Array(skills[index].recentResults.suffix(5))

        let totalAccuracy = skills[index].accuracy * 100
        let recentAccuracy = recentAccuracy(for: skills[index].recentResults)
        skills[index].mastery = totalAccuracy * 0.7 + recentAccuracy * 0.3
        skills[index].status = status(for: skills[index].mastery, attempts: skills[index].totalAttempts)
        unlockNextSkill(after: index)
    }

    private func addSimilarExercise(from result: GradingResult, skillID: UUID) {
        let exercise = Exercise(
            id: UUID(),
            skillID: skillID,
            chineseSentence: result.similarQuestionCN,
            referenceAnswer: result.betterVersion,
            difficulty: 2
        )
        exercises.insert(exercise, at: 0)
    }

    private func unlockNextSkill(after index: Int) {
        guard skills[index].mastery >= 80 else { return }
        let nextIndex = skills.index(after: index)
        guard skills.indices.contains(nextIndex), skills[nextIndex].status == .locked else { return }
        skills[nextIndex].status = .available
    }

    private func recentAccuracy(for results: [Bool]) -> Double {
        guard !results.isEmpty else { return 0 }
        let correct = results.filter { $0 }.count
        return Double(correct) / Double(results.count) * 100
    }

    private func status(for mastery: Double, attempts: Int) -> SkillStatus {
        guard attempts > 0 else { return .available }
        switch mastery {
        case 0..<40:
            return .review
        case 40..<60:
            return .training
        case 60..<80:
            return .basic
        default:
            return .proficient
        }
    }

    private func recommendationScore(for skill: GrammarSkill) -> Double {
        let errorCount = Double(max(skill.totalAttempts - skill.correctAttempts, 0))
        let recentPenalty = skill.recentResults.suffix(3).filter { !$0 }.count
        return errorCount + Double(recentPenalty) * 1.5 + Double(skill.difficulty) - skill.mastery / 100
    }
}

enum GrammarSeed {
    static func make() -> (skills: [GrammarSkill], exercises: [Exercise]) {
        let skills = [
            GrammarSkill(id: UUID(), module: "句子骨架", name: "主谓宾结构", description: "写出结构完整、语序正确的简单句。", difficulty: 1, mastery: 91, totalAttempts: 12, correctAttempts: 11, repeatErrorCount: 1, recentResults: [true, true, true, true, true], status: .proficient),
            GrammarSkill(id: UUID(), module: "时态系统", name: "现在完成时", description: "表达过去发生并影响现在的动作。", difficulty: 2, mastery: 64, totalAttempts: 8, correctAttempts: 5, repeatErrorCount: 3, recentResults: [false, true, false, true, true], status: .training),
            GrammarSkill(id: UUID(), module: "从句系统", name: "定语从句", description: "用从句补充说明名词，使表达更紧凑。", difficulty: 3, mastery: 52, totalAttempts: 6, correctAttempts: 3, repeatErrorCount: 3, recentResults: [false, false, true, true, false], status: .training),
            GrammarSkill(id: UUID(), module: "介词搭配", name: "时间介词", description: "稳定区分 in、on、at、for、since。", difficulty: 2, mastery: 48, totalAttempts: 5, correctAttempts: 2, repeatErrorCount: 3, recentResults: [false, true, false, false, true], status: .review),
            GrammarSkill(id: UUID(), module: "非谓语", name: "to do 作目的", description: "用不定式表达目的和意图。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked),
            GrammarSkill(id: UUID(), module: "表达升级", name: "因果表达", description: "用自然的连接方式说明原因和结果。", difficulty: 4, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked)
        ]

        let exercises = [
            Exercise(id: UUID(), skillID: skills[0].id, chineseSentence: "我每天阅读英文文章。", referenceAnswer: "I read English articles every day.", difficulty: 1),
            Exercise(id: UUID(), skillID: skills[1].id, chineseSentence: "我已经学习英语三个月了。", referenceAnswer: "I have been learning English for three months.", difficulty: 2),
            Exercise(id: UUID(), skillID: skills[2].id, chineseSentence: "这是我昨天买的那本书。", referenceAnswer: "This is the book that I bought yesterday.", difficulty: 3),
            Exercise(id: UUID(), skillID: skills[3].id, chineseSentence: "他从 2020 年起就住在上海。", referenceAnswer: "He has lived in Shanghai since 2020.", difficulty: 2),
            Exercise(id: UUID(), skillID: skills[4].id, chineseSentence: "我学习英语是为了出国交流。", referenceAnswer: "I study English to communicate abroad.", difficulty: 3),
            Exercise(id: UUID(), skillID: skills[5].id, chineseSentence: "因为下雨，比赛被推迟了。", referenceAnswer: "The match was postponed because it rained.", difficulty: 4)
        ]

        return (skills, exercises)
    }
}
