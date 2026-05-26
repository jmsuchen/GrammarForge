import SwiftUI

struct SkillTreeView: View {
    @EnvironmentObject private var store: GrammarStore

    var body: some View {
        List {
            ForEach(groupedModules, id: \.module) { section in
                Section(section.module) {
                    ForEach(section.skills) { skill in
                        Button {
                            store.select(skill)
                        } label: {
                            SkillRow(skill: skill, isSelected: store.selectedSkillID == skill.id)
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
        var sections: [(module: String, skills: [GrammarSkill])] = []
        for skill in store.skills {
            if let index = sections.firstIndex(where: { $0.module == skill.module }) {
                sections[index].skills.append(skill)
            } else {
                sections.append((module: skill.module, skills: [skill]))
            }
        }
        return sections
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
