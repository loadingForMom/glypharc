//
//  AppContainer.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//

import Foundation

@MainActor
final class AppContainer {
    let appState: AppState
    let overlay: OverlayPanelController
    let selectionMonitor: SelectionMonitor
    let permissionManager: PermissionManager

    let resultPanel: ResultPanelController

    init() {
        self.appState = AppState()
        self.overlay = OverlayPanelController(appState: appState)
        self.permissionManager = PermissionManager()
        self.selectionMonitor = SelectionMonitor(appState: appState, overlay: overlay)
        self.resultPanel = ResultPanelController(appState: appState)
    }
}
