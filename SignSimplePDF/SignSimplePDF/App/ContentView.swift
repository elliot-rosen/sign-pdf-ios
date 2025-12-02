import SwiftUI

struct ContentView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var signatureManager: SignatureManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "doc.text.fill" : "doc.text")
                    Text("Documents")
                }
                .tag(0)

            SignatureView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "signature" : "signature")
                    Text("Signatures")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "gear.circle.fill" : "gear.circle")
                    Text("Settings")
                }
                .tag(2)
        }
        .accentColor(AppTheme.Colors.primary)
        .onChange(of: selectedTab) { _, newValue in
            HapticManager.shared.selection()
        }
        .preferredColorScheme(nil) // Allow system color scheme
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let subscriptionManager = SubscriptionManager()
        ContentView()
            .environmentObject(subscriptionManager)
            .environmentObject(DocumentManager())
            .environmentObject(SignatureManager(subscriptionManager: subscriptionManager))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
