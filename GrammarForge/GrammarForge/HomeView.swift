import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: GrammarStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GrammarForge")
                        .font(.largeTitle.bold())
                    Text("把语法知识练成稳定输出能力")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(title: "当前能力等级", value: store.currentStage, systemImage: "flag.checkered")
                    MetricCard(title: "整体正确率", value: "\(Int(store.overallAccuracy * 100))%", systemImage: "target")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("推荐训练")
                        .font(.title2.bold())

                    ForEach(store.recommendations) { recommendation in
                        Button {
                            store.select(recommendation.skill)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(recommendation.skill.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int(recommendation.skill.mastery))%")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text(recommendation.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("近期薄弱点")
                        .font(.title2.bold())
                    FlowTags(items: store.weakPoints)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("今日建议", systemImage: "sparkle.magnifyingglass")
                        .font(.headline)
                    Text("完成任意一组中译英训练即可。系统会按真实表现更新掌握度，而不是按固定日期推进。")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.indigo.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
        .navigationTitle("首页")
    }
}

private struct FlowTags: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HomeView()
                .environmentObject(GrammarStore())
        }
    }
}
