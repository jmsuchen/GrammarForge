import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }

            NavigationStack {
                SkillTreeView()
            }
            .tabItem {
                Label("能力树", systemImage: "tree")
            }

            NavigationStack {
                PracticeView()
            }
            .tabItem {
                Label("训练", systemImage: "pencil.and.list.clipboard")
            }

            NavigationStack {
                MistakeBookView()
            }
            .tabItem {
                Label("错题本", systemImage: "book.closed")
            }

            NavigationStack {
                ReportView()
            }
            .tabItem {
                Label("报告", systemImage: "chart.bar.doc.horizontal")
            }
        }
        .tint(.indigo)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(GrammarStore())
    }
}
