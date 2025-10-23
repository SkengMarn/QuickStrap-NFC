//
//  NFCDemoApp.swift
//  NFCDemo
//
//  Created by Jew on 24/09/2025.
//

import SwiftUI

@main
struct NFCDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var broadcastService = BroadcastService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(broadcastService)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
                }
        }
    }

    /// Handle app lifecycle changes
    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("🟢 App became active")
            // App is in the foreground and active

        case .inactive:
            print("🟡 App became inactive")
            // App is in the foreground but not active (e.g., phone call, notification center)

        case .background:
            print("🔴 App moved to background")
            // App is in the background
            // Broadcast service will continue running in background for a short time

        @unknown default:
            print("⚪ App phase unknown")
        }
    }
}

/// App delegate for handling app termination
class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        print("🛑 App will terminate - cleaning up broadcast service")
        BroadcastService.shared.cleanup()
    }
}
