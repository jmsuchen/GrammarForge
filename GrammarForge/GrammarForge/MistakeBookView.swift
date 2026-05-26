import SwiftUI

struct MistakeBookView: View {
    @EnvironmentObject private var store: GrammarStore

    var body: some View {
        List {
            if mistakes.isEmpty {
                EmptyStateView(title: "还没有错题", subtitle: "完成一次训练后，错误会自动按语法点和错误类型沉淀到这里。", systemImage: "book")
                    .listRowBackground(Color.clear)
            } else {
                Section("按语法点") {
                    ForEach(groupBySkill, id: \.skill) { group in
                        NavigationLink {
                            MistakeGroupView(title: group.skill, submissions: group.submissions)
                        } label: {
                            HStack {
                                Text(group.skill)
                                Spacer()
                                Text("\(group.submissions.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("按错误类型") {
                    ForEach(groupByErrorType, id: \.type) { group in
                        NavigationLink {
                            MistakeGroupView(title: group.type, submissions: group.submissions)
                        } label: {
                            HStack {
                                Text(group.type)
                                Spacer()
                                Text("\(group.submissions.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("错题本")
    }

    private var mistakes: [Submission] {
        store.submissions.filter { !$0.result.isCorrect }
    }

    private var groupBySkill: [(skill: String, submissions: [Submission])] {
        Dictionary(grouping: mistakes, by: \.skillName)
            .map { ($0.key, $0.value) }
            .sorted { $0.skill < $1.skill }
    }

    private var groupByErrorType: [(type: String, submissions: [Submission])] {
        let pairs = mistakes.flatMap { submission in
            submission.result.errorTypes.map { ($0, submission) }
        }
        return Dictionary(grouping: pairs, by: \.0)
            .map { (type: $0.key, submissions: $0.value.map(\.1)) }
            .sorted { $0.type < $1.type }
    }
}

private struct MistakeGroupView: View {
    let title: String
    let submissions: [Submission]

    var body: some View {
        List(submissions) { submission in
            VStack(alignment: .leading, spacing: 8) {
                Text(submission.exercise.chineseSentence)
                    .font(.headline)
                    .textSelection(.enabled)
                SelectableMistakeText(title: "你的答案", value: submission.userAnswer)
                SelectableMistakeText(title: "推荐答案", value: submission.result.correctedSentence)
                SelectableMistakeText(title: "推荐句式", value: submission.result.betterVersion)
                SelectableMistakeText(title: "中文解释", value: submission.result.explanationCN)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle(title)
    }
}

private struct SelectableMistakeText: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}

struct MistakeBookView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MistakeBookView()
                .environmentObject(GrammarStore())
        }
    }
}
