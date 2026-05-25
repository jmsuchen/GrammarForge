import SwiftUI

struct PracticeView: View {
    @EnvironmentObject private var store: GrammarStore
    @State private var answer = ""
    @State private var isSubmitting = false
    @State private var latestResult: GradingResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let skill = store.selectedSkill, let exercise = store.currentExercise {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(skill.name)
                            .font(.largeTitle.bold())
                        Text(skill.description)
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
                        Text("请输入英文")
                            .font(.headline)
                        TextEditor(text: $answer)
                            .frame(minHeight: 130)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.quaternary)
                            }
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
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

                    if let latestResult {
                        ResultView(result: latestResult)
                    }
                } else {
                    EmptyStateView(title: "暂无可训练语法点", subtitle: "请先在能力树中选择一个已解锁的语法点。", systemImage: "lock")
                }
            }
            .padding()
        }
        .navigationTitle("中译英训练")
    }

    private func submit() {
        isSubmitting = true
        latestResult = nil
        let submittedAnswer = answer
        Task {
            await store.submitCurrentAnswer(submittedAnswer)
            latestResult = store.submissions.first?.result
            answer = ""
            isSubmitting = false
        }
    }
}

private struct ResultView: View {
    let result: GradingResult

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
                Text("推荐答案")
                    .font(.subheadline.weight(.semibold))
                Text(result.correctedSentence)
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
