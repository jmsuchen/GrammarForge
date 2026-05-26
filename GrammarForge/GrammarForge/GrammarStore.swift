import Foundation

@MainActor
final class GrammarStore: ObservableObject {
    @Published private(set) var skills: [GrammarSkill]
    @Published private(set) var exercises: [Exercise]
    @Published private(set) var submissions: [Submission] = []
    @Published var selectedSkillID: UUID?
    @Published private var selectedExerciseID: UUID?
    @Published private var activeExerciseIDs: [UUID] = []
    @Published private var activeExerciseIndex = 0
    @Published private(set) var draftAnswer = ""
    @Published private(set) var activeVocabularyLevel: VocabularyLevel = .cet4
    @Published private(set) var shouldShowDailyEncouragement = false

    private let gradingService: AIGradingService
    private let exerciseSetSize = 10
    private let dailyPracticeGoalSeconds = 20 * 60
    private let storageKey = "grammarforge.learning_state.v4"
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
            self.activeExerciseIDs = state.activeExerciseIDs
            self.activeExerciseIndex = state.activeExerciseIndex
            self.draftAnswer = state.draftAnswer
            self.activeVocabularyLevel = state.activeVocabularyLevel
            self.dailyPracticeDate = state.dailyPracticeDate
            self.dailyPracticeSeconds = state.dailyPracticeSeconds
            self.didShowDailyEncouragement = state.didShowDailyEncouragement
            resetDailyPracticeIfNeeded()
        } else {
            let skills = GrammarSeed.make()
            let initialSkillID = skills.first(where: { $0.status != .locked })?.id
            self.skills = skills
            self.exercises = []
            self.selectedSkillID = initialSkillID
            self.selectedExerciseID = nil
            self.activeExerciseIDs = []
            self.activeExerciseIndex = 0
            self.draftAnswer = ""
            self.activeVocabularyLevel = .cet4
            self.dailyPracticeDate = Self.todayKey()
            self.dailyPracticeSeconds = 0
            self.didShowDailyEncouragement = false
            saveState()
        }
    }

    private var dailyPracticeDate: String
    private var dailyPracticeSeconds: Int
    private var didShowDailyEncouragement: Bool

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

    var exerciseSetProgressText: String {
        guard !activeExerciseIDs.isEmpty else { return "0 / \(exerciseSetSize)" }
        return "\(min(activeExerciseIndex + 1, activeExerciseIDs.count)) / \(activeExerciseIDs.count)"
    }

    var hasNextExerciseInSet: Bool {
        activeExerciseIndex + 1 < activeExerciseIDs.count
    }

    var hasActiveExerciseSet: Bool {
        !activeExerciseIDs.isEmpty && currentExercise != nil
    }

    var latestSubmissionForCurrentExercise: Submission? {
        guard let currentExercise else { return nil }
        return submissions.first { $0.exercise.id == currentExercise.id }
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
        activeExerciseIDs = []
        activeExerciseIndex = 0
        draftAnswer = ""
        saveState()
    }

    func generateExerciseSet(vocabularyLevel: VocabularyLevel) async {
        guard let skill = selectedSkill else { return }
        let generatedExercises = await gradingService.generateExerciseSet(for: skill, vocabularyLevel: vocabularyLevel, count: exerciseSetSize)
        exercises.insert(contentsOf: generatedExercises, at: 0)
        activeExerciseIDs = generatedExercises.map(\.id)
        activeExerciseIndex = 0
        selectedExerciseID = activeExerciseIDs.first
        activeVocabularyLevel = vocabularyLevel
        draftAnswer = ""
        saveState()
    }

    func moveToNextExerciseInSet() {
        guard hasNextExerciseInSet else { return }
        activeExerciseIndex += 1
        selectedExerciseID = activeExerciseIDs[activeExerciseIndex]
        draftAnswer = ""
        saveState()
    }

    func clearActiveExerciseSet() {
        activeExerciseIDs = []
        activeExerciseIndex = 0
        selectedExerciseID = nil
        draftAnswer = ""
        saveState()
    }

    func updateDraftAnswer(_ answer: String) {
        draftAnswer = answer
        saveState()
    }

    func recordPracticeSecond() {
        resetDailyPracticeIfNeeded()
        guard !didShowDailyEncouragement else { return }
        dailyPracticeSeconds += 1
        if dailyPracticeSeconds >= dailyPracticeGoalSeconds {
            didShowDailyEncouragement = true
            shouldShowDailyEncouragement = true
        }
        saveState()
    }

    func dismissDailyEncouragement() {
        shouldShowDailyEncouragement = false
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
        draftAnswer = ""
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
            selectedExerciseID: selectedExerciseID,
            activeExerciseIDs: activeExerciseIDs,
            activeExerciseIndex: activeExerciseIndex,
            draftAnswer: draftAnswer,
            activeVocabularyLevel: activeVocabularyLevel,
            dailyPracticeDate: dailyPracticeDate,
            dailyPracticeSeconds: dailyPracticeSeconds,
            didShowDailyEncouragement: didShowDailyEncouragement
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

    private func resetDailyPracticeIfNeeded() {
        let today = Self.todayKey()
        guard dailyPracticeDate != today else { return }
        dailyPracticeDate = today
        dailyPracticeSeconds = 0
        didShowDailyEncouragement = false
        shouldShowDailyEncouragement = false
        saveState()
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct LearningState: Codable {
    let skills: [GrammarSkill]
    let exercises: [Exercise]
    let submissions: [Submission]
    let selectedSkillID: UUID?
    let selectedExerciseID: UUID?
    let activeExerciseIDs: [UUID]
    let activeExerciseIndex: Int
    let draftAnswer: String
    let activeVocabularyLevel: VocabularyLevel
    let dailyPracticeDate: String
    let dailyPracticeSeconds: Int
    let didShowDailyEncouragement: Bool
}

enum GrammarSeed {
    static func make() -> [GrammarSkill] {
        [
            GrammarSkill(id: UUID(uuidString: "64E64625-7CB0-4E6D-9B48-7CC5F4E596F0")!, module: "01 句子骨架", name: "主谓宾基础", description: "训练最基本的 SVO 语序，避免中文语序直译。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "7B97A0C0-47CC-4C7C-90B2-251775DC1A01")!, module: "01 句子骨架", name: "主系表结构", description: "用 be、seem、become 等连接主语和状态/身份。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "D28F8717-A5EC-49F7-A79F-A55271D48D01")!, module: "01 句子骨架", name: "双宾语结构", description: "训练 give/send/tell/show 等动词后的人和物的顺序。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "8E56C513-8074-44D4-A36E-6DB490949B01")!, module: "01 句子骨架", name: "There be 句型", description: "表达某处有某物，并稳定处理单复数。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "B533F19D-5F79-40E6-9DC7-2BB2E3303FC7")!, module: "02 时态系统", name: "一般现在时", description: "表达习惯、事实和稳定状态，注意第三人称单数。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "87FD49A7-CAD9-49F7-A915-B2EFBDBD6E02")!, module: "02 时态系统", name: "一般过去时", description: "表达过去完成的动作，训练动词过去式和时间状语。", difficulty: 1, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "AA61BE6F-C01E-4C7B-A277-B56F3A117A03")!, module: "02 时态系统", name: "现在进行时", description: "表达正在发生或阶段性进行的动作。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "192757F3-D238-4486-8192-B62A8101C104")!, module: "02 时态系统", name: "现在完成时", description: "表达过去动作对现在的影响，区分 for 和 since。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "96C71F37-63DE-4C46-B35E-FDAB2EAE4BB8")!, module: "03 介词搭配", name: "时间介词 in/on/at", description: "稳定区分年月、日期、具体时间点前的介词。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "AC589752-5444-43F4-A9E1-BED81F33D105")!, module: "03 介词搭配", name: "地点介词 in/on/at", description: "表达地点、表面、位置点，避免中文泛化成 in。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "98D6F0FA-7053-4C6B-BD0F-9E213B051A06")!, module: "03 介词搭配", name: "动词介词搭配", description: "训练 depend on、listen to、look for 等常用搭配。", difficulty: 2, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "7F8E6C0A-B777-4663-B4B8-730AB0333B64")!, module: "04 从句系统", name: "宾语从句语序", description: "训练 I think/know/wonder 后的陈述语序。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "2FB75F58-C654-44B5-946B-63C58324F207")!, module: "04 从句系统", name: "定语从句 who/that", description: "用从句补充说明人或物，避免两个句子硬拼。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "829A4440-E3CE-41CB-B292-79CC483A9208")!, module: "04 从句系统", name: "原因状语从句", description: "用 because/since/as 表达原因和主句关系。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "9EB5E5B6-1377-4D65-AD5B-C3E4B0B54E09")!, module: "04 从句系统", name: "条件状语从句", description: "训练 if/unless 引导的真实条件，注意主将从现。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "42B6C20F-E36A-4CE1-844A-80C1FDCBFF60")!, module: "05 非谓语", name: "to do 表目的", description: "用不定式表达目的、计划和意图。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "8A5D8FA2-B022-487B-BD91-A3551A108110")!, module: "05 非谓语", name: "doing 作主语/宾语", description: "训练动名词作主语或动词宾语的自然表达。", difficulty: 3, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "69C0A873-03CB-4D25-8E5A-D44B70AF0511")!, module: "05 非谓语", name: "分词作定语", description: "用 -ing/-ed 分词修饰名词，提高表达紧凑度。", difficulty: 4, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "C8E9E84F-36C8-44DA-9DF0-09FF8B385965")!, module: "06 表达升级", name: "因果连接", description: "用 because/therefore/as a result 表达原因和结果。", difficulty: 4, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "7C76D969-C0F3-40C1-9043-906C74673B12")!, module: "06 表达升级", name: "让步转折", description: "用 although/however/despite 表达转折和让步。", difficulty: 4, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "9B4B7754-4328-4F54-830D-B7EB313DB313")!, module: "06 表达升级", name: "比较对比", description: "用 than、compared with、whereas 做清楚对比。", difficulty: 4, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available),
            GrammarSkill(id: UUID(uuidString: "0922FC9E-7DBF-4625-94F9-F868FE463B14")!, module: "06 表达升级", name: "观点论证", description: "训练提出观点、补充理由和给出例子的句式。", difficulty: 5, mastery: 0, totalAttempts: 0, correctAttempts: 0, repeatErrorCount: 0, recentResults: [], status: .available)
        ]
    }
}
