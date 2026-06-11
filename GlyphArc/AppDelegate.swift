//
//  AppDelegate.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//


import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Старт мониторинга выделения
        container.selectionMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.selectionMonitor.stop()
    }
}
