import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var store: GrammarStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("阶段学习报告")
                        .font(.largeTitle.bold())
                    Text("报告按训练进展触发，不按固定周/月生成。")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(title: "已完成句子", value: "\(store.submissions.count)", systemImage: "checklist")
                    MetricCard(title: "整体正确率", value: "\(Int(store.overallAccuracy * 100))%", systemImage: "chart.line.uptrend.xyaxis")
                }

                ReportSection(title: "进步明显的地方", items: strengths)
                ReportSection(title: "当前薄弱点", items: store.weakPoints)
                ReportSection(title: "下一步建议", items: nextSteps)
            }
            .padding()
        }
        .navigationTitle("报告")
    }

    private var strengths: [String] {
        let mastered = store.skills
            .filter { $0.mastery >= 80 }
            .map { "\($0.name) 使用更稳定。" }
        return mastered.isEmpty ? ["完成训练后生成。"] : mastered
    }

    private var nextSteps: [String] {
        store.recommendations.map { "优先复练 \($0.skill.name)。" }
    }
}

private struct ReportSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ReportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ReportView()
                .environmentObject(GrammarStore())
        }
    }
}
