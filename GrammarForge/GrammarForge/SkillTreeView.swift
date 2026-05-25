import SwiftUI

struct SkillTreeView: View {
    @EnvironmentObject private var store: GrammarStore

    var body: some View {
        List {
            ForEach(groupedModules, id: \.module) { section in
                Section(section.module) {
                    ForEach(section.skills) { skill in
                        Button {
                            guard skill.status != .locked else { return }
                            store.select(skill)
                        } label: {
                            SkillRow(skill: skill, isSelected: store.selectedSkillID == skill.id)
                                .opacity(skill.status == .locked ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("能力树")
    }

    private var groupedModules: [(module: String, skills: [GrammarSkill])] {
        Dictionary(grouping: store.skills, by: \.module)
            .map { ($0.key, $0.value) }
            .sorted { $0.module < $1.module }
    }
}

struct SkillTreeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SkillTreeView()
                .environmentObject(GrammarStore())
        }
    }
}
