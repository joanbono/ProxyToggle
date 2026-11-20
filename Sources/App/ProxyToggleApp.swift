import SwiftUI
import UIKit

@main
struct ProxyToggleApp: App {
    @StateObject private var model = ProxyModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { model.handle($0) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    model.refresh()
                }
        }
    }
}
