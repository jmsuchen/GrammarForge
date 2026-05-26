import Foundation

@MainActor
final class GrammarStore: ObservableObject {
    @Published private(set) var skills: [GrammarSkill]
    @Published private(set) var exercises: [Exercise]
    @Published private(set) var submissions: [Submission] = []
    @Published var selectedSkillID: UUID?
    @Published private var selectedExerciseID: UUID?

    private let gradingService: AIGradingService
    private let storageKey = "grammarforge.learning_state.v1"
    private let clearDataSettingsKey = "clear_learning_data"

    init(gradingService: AIGradingService = BackendAIGradingService()) {
        self.gradingService = gradingService
        if UserDefaults.standard.bool(forKey: clearDataSettingsKey) {
            Self.clearPersistedState(storageKey: storageKey)
            UserDefaults.standard.set(false, forKey: clearDataSettingsKey)
        }

        if let state = Self.loadState(storageKey: storageKey) {
            self.skills = state.skills
            self.exercises = state.exercises
            self.submissions = state.submissions
            self.selectedSkillID = state.selectedSkillID
            self.selectedExerciseID = state.selectedExerciseID
        } else {
            let skills = GrammarSeed.make()
            let initialSkillID = skills.first(where: { $0.status != .locked })?.id
            self.skills = skills
            self.exercises = []
            self.selectedSkillID = initialSkillID
            self.selectedExerciseID = nil
            saveState()
        }
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
        if let selectedExerciseID,
           let selectedExercise = exercises.first(where: { $0.id == selectedExerciseID && $0.skillID == selectedSkillID }) {
            return selectedExercise
        }
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
                    reason: recommendationReason(for: skill)
                )
            }
    }

    var weakPoints: [String] {
        let recentErrors = submissions.flatMap { $0.result.errorTypes }
        if recentErrors.isEmpty {
            return ["完成首次训练后生成"]
        }
        return Array(Dictionary(grouping: recentErrors, by: { $0 })
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map(\.key))
    }

    var overallAccuracy: Double {
        guard !submissions.isEmpty else { return 0 }
        let correct = submissions.filter { $0.result.isCorrect }.count
        return Double(correct) / Double(submissions.count)
    }

    func select(_ skill: GrammarSkill) {
        selectedSkillID = skill.id
        selectedExerciseID = exercises.first { $0.skillID == skill.id }?.id
        saveState()
    }

    func generateExercise(vocabularyLevel: VocabularyLevel) async {
        guard let skill = selectedSkill else { return }
        let exercise = await gradingService.generateExercise(for: skill, vocabularyLevel: vocabularyLevel)
        exercises.insert(exercise, at: 0)
        selectedExerciseID = exercise.id
        saveState()
    }

    func submitCurrentAnswer(_ answer: String, vocabularyLevel: VocabularyLevel) async {
        guard let skill = selectedSkill, let exercise = currentExercise else { return }
        let result = await gradingService.grade(answer: answer, exercise: exercise, skill: skill, vocabularyLevel: vocabularyLevel)
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
        saveState()
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
        guard skill.totalAttempts > 0 else {
            return skill.status == .available ? 10 - Double(skill.difficulty) : 0
        }
        let errorCount = Double(max(skill.totalAttempts - skill.correctAttempts, 0))
        let recentPenalty = skill.recentResults.suffix(3).filter { !$0 }.count
        return errorCount + Double(recentPenalty) * 1.5 + Double(skill.difficulty) - skill.mastery / 100
    }

    private func recommendationReason(for skill: GrammarSkill) -> String {
        if skill.totalAttempts == 0 {
            return "从这里开始完成第一组中译英训练。"
        }
        return skill.mastery < 60 ? "掌握度偏低，适合继续输出训练。" : "近期仍有错误，适合做相似题巩固。"
    }

    private func saveState() {
        let state = LearningState(
            skills: skills,
            exercises: exercises,
            submissions: submissions,
            selectedSkillID: selectedSkillID,
            selectedExerciseID: selectedExerciseID
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadState(storageKey: String) -> LearningState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(LearningState.self, from: data)
    }

    private static func clearPersistedState(storageKey: String) {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

private struct LearningState: Codable {
    let skills: [GrammarSkill]
    let exercises: [Exercise]
    let submissions: [Submission]
    let selectedSkillID: UUID?
    let selectedExerciseID: UUID?
}

enum GrammarSeed {
    static func make() -> [GrammarSkill] {
        [
            GrammarSkill(id: UUID(uuidString: "64E64625-7CB0-4E6D-9B48-7CC5F4E596F0")!, module: "句子骨架", name: "主谓宾结构", description: "写出结构完整、语序正确的简单句。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "B533F19D-5F79-40E6-9DC7-2BB2E3303FC7")!, module: "时态系统", name: "现在完成时", description: "表达过去发生并影响现在的动作。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked),
            GrammarSkill(id: UUID(uuidString: "7F8E6C0A-B777-4663-B4B8-730AB0333B64")!, module: "从句系统", name: "定语从句", description: "用从句补充说明名词，使表达更紧凑。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked),
            GrammarSkill(id: UUID(uuidString: "96C71F37-63DE-4C46-B35E-FDAB2EAE4BB8")!, module: "介词搭配", name: "时间介词", description: "稳定区分 in、on、at、for、since。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked),
            GrammarSkill(id: UUID(uuidString: "42B6C20F-E36A-4CE1-844A-80C1FDCBFF60")!, module: "非谓语", name: "to do 作目的", description: "用不定式表达目的和意图。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked),
            GrammarSkill(id: UUID(uuidString: "C8E9E84F-36C8-44DA-9DF0-09FF8B385965")!, module: "表达升级", name: "因果表达", description: "用自然的连接方式说明原因和结果。", difficulty: 4, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .locked)
        ]
    }
}
