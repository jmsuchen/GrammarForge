import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct PracticeView: View {
    @EnvironmentObject private var store: GrammarStore
    @State private var answer = ""
    @State private var isGeneratingExercise = false
    @State private var isSubmitting = false
    @State private var latestSubmission: Submission?
    @State private var vocabularyLevel: VocabularyLevel = .cet4
    @State private var isExerciseStarted = false
    @State private var generationToken: UUID?
    @FocusState private var isAnswerFocused: Bool
    private let practiceTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let skill = store.selectedSkill {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(skill.name)
                                .font(.largeTitle.bold())
                            Text(skill.description)
                                .foregroundStyle(.secondary)
                        }

                        if !isExerciseStarted {
                            Text("造句词汇难度")
                                .font(.headline)
                            Picker("造句词汇难度", selection: $vocabularyLevel) {
                                ForEach(VocabularyLevel.allCases) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(vocabularyLevel.promptDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                startExercise()
                            } label: {
                                HStack {
                                    if isGeneratingExercise {
                                        ProgressView()
                                    }
                                    Label(isGeneratingExercise ? "生成 10 题中" : "开始一组 10 题", systemImage: "play.fill")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isGeneratingExercise)
                        } else if let exercise = store.currentExercise {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(vocabularyLevel.rawValue, systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(store.exerciseSetProgressText)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Button("重新选难度") {
                                        resetToLevelSelection()
                                    }
                                    .font(.subheadline.weight(.medium))
                                }
                                Text(vocabularyLevel.promptDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Label("中文句子", systemImage: "text.quote")
                                    .font(.headline)
                                Text(exercise.chineseSentence)
                                    .font(.title3.weight(.semibold))
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("请输入英文")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        hideKeyboard()
                                    } label: {
                                        Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                                    }
                                    .font(.subheadline.weight(.medium))
                                }
                                TextEditor(text: $answer)
                                    .focused($isAnswerFocused)
                                    .frame(minHeight: 130)
                                    .padding(8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.quaternary)
                                    }
                                    .submitLabel(.done)
                            }

                            Button {
                                submit()
                            } label: {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                    }
                                    Label(isSubmitting ? "批改中" : "提交批改", systemImage: "paperplane.fill")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting || latestSubmission != nil)

                            if let latestSubmission {
                                ResultView(submission: latestSubmission)

                                HStack(spacing: 12) {
                                    Button {
                                        resetToLevelSelection()
                                    } label: {
                                        Label("重新选难度", systemImage: "slider.horizontal.3")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        nextExercise()
                                    } label: {
                                        HStack {
                                            if isGeneratingExercise {
                                                ProgressView()
                                            }
                                            Label(nextButtonTitle, systemImage: "arrow.right.circle.fill")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isGeneratingExercise)
                                }
                            }
                        }
                    } else {
                        EmptyStateView(title: "暂无可训练语法点", subtitle: "请先在能力树中选择一个已解锁的语法点。", systemImage: "lock")
                    }
                }
                .padding()
            }

            if store.shouldShowDailyEncouragement {
                DailyEncouragementView {
                    store.dismissDailyEncouragement()
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationTitle("中译英训练")
        .onAppear {
            restorePracticeState()
        }
        .onReceive(practiceTimer) { _ in
            guard isExerciseStarted else { return }
            store.recordPracticeSecond()
        }
        .onChange(of: answer) { _, newValue in
            guard isExerciseStarted, latestSubmission == nil else { return }
            store.updateDraftAnswer(newValue)
        }
        .onChange(of: store.selectedSkillID) { _, _ in
            resetToLevelSelection()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    hideKeyboard()
                }
            }
        }
    }

    private func startExercise() {
        guard !isGeneratingExercise else { return }
        answer = ""
        latestSubmission = nil
        isGeneratingExercise = true
        let token = UUID()
        generationToken = token
        Task {
            await store.generateExerciseSet(vocabularyLevel: vocabularyLevel)
            guard generationToken == token else { return }
            isGeneratingExercise = false
            isExerciseStarted = true
        }
    }

    private func submit() {
        hideKeyboard()
        isSubmitting = true
        latestSubmission = nil
        let submittedAnswer = answer
        let selectedVocabularyLevel = vocabularyLevel
        Task {
            await store.submitCurrentAnswer(submittedAnswer, vocabularyLevel: selectedVocabularyLevel)
            latestSubmission = store.submissions.first
            answer = ""
            isSubmitting = false
        }
    }

    private func nextExercise() {
        guard !isGeneratingExercise else { return }
        hideKeyboard()
        answer = ""
        latestSubmission = nil
        if store.hasNextExerciseInSet {
            store.moveToNextExerciseInSet()
        } else {
            resetToLevelSelection()
        }
    }

    private func resetToLevelSelection() {
        hideKeyboard()
        answer = ""
        latestSubmission = nil
        isSubmitting = false
        isGeneratingExercise = false
        generationToken = nil
        isExerciseStarted = false
        store.clearActiveExerciseSet()
    }

    private func restorePracticeState() {
        vocabularyLevel = store.activeVocabularyLevel
        answer = store.draftAnswer
        isExerciseStarted = store.hasActiveExerciseSet
        latestSubmission = store.latestSubmissionForCurrentExercise
    }

    private func hideKeyboard() {
        isAnswerFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

private struct DailyEncouragementView: View {
    let onDismiss: () -> Void
    @State private var pulse = false
    @State private var speaker = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.yellow)
                    .scaleEffect(pulse ? 1.14 : 0.92)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

                Text("今天已经认真练习 20 分钟")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("你不是在刷题，是在把英语输出能力一点点练稳。今天这一步很扎实。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    speaker.stopSpeaking(at: .immediate)
                    onDismiss()
                } label: {
                    Label("继续训练", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 18)
            .padding()
        }
        .onAppear {
            pulse = true
            let utterance = AVSpeechUtterance(string: "太棒了，你今天已经认真练习二十分钟了，继续保持。")
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.48
            speaker.speak(utterance)
        }
    }
}

private extension PracticeView {
    var nextButtonTitle: String {
        if isGeneratingExercise {
            return "生成 10 题中"
        }
        return store.hasNextExerciseInSet ? "下一题" : "完成本组"
    }
}

private struct ResultView: View {
    let submission: Submission

    private var result: GradingResult {
        submission.result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(result.isCorrect ? "基本正确" : "需要复练", systemImage: result.isCorrect ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(result.isCorrect ? .green : .orange)
                Spacer()
                Text("\(result.score)")
                    .font(.title.bold())
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("你的输入")
                    .font(.subheadline.weight(.semibold))
                Text(submission.userAnswer)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("推荐答案")
                    .font(.subheadline.weight(.semibold))
                Text(result.correctedSentence)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("推荐句式")
                    .font(.subheadline.weight(.semibold))
                Text(result.betterVersion)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("中文解释")
                    .font(.subheadline.weight(.semibold))
                Text(result.explanationCN)
                    .foregroundStyle(.secondary)
            }

            if !result.errorTypes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("错误类型")
                        .font(.subheadline.weight(.semibold))
                    Text(result.errorTypes.joined(separator: "、"))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("相似题")
                    .font(.subheadline.weight(.semibold))
                Text(result.similarQuestionCN)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PracticeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PracticeView()
                .environmentObject(GrammarStore())
        }
    }
}
