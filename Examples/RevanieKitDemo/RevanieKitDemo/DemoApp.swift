import SwiftUI
import RevanieKit

/// A small paywall on RevanieKit. Run it with the Demo.storekit configuration (scheme › Run › Options › StoreKit
/// Configuration) and your own SDK key, or let the tests drive it against a local Revanie server.
@main
struct DemoApp: App {
    var body: some Scene { WindowGroup { PaywallDemo() } }
}

struct PaywallDemo: View {
    @State private var packages: [Package] = []
    @State private var pro = false
    @State private var message = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(pro ? "Pro is unlocked" : "RevanieKit Demo").font(.title2.weight(.semibold))
            ForEach(packages) { p in
                Button("\(p.product.displayName) · \(p.product.displayPrice)") {
                    Task {
                        do {
                            if case .purchased(let info, _) = try await Revanie.shared.purchase(p) { pro = info.isActive("pro") }
                        } catch { message = "\(error)" }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Restore purchases") { Task { pro = (try? await Revanie.shared.restorePurchases().isActive("pro")) ?? pro } }
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .task {
            guard Revanie.isConfigured else { message = "Call Revanie.configure(apiKey:) with your SDK key."; return }
            packages = (try? await Revanie.shared.offerings().current?.packages) ?? []
            pro = (try? await Revanie.shared.customerInfo().isActive("pro")) ?? false
        }
    }
}
