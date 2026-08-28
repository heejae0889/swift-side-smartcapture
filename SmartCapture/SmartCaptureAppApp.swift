import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureExecution = Self("captureExecution")
    static let openSettings = Self("openSettings", default: .init(.o, modifiers: [.option]))
}

@main
struct SmartCaptureAppApp: App {
    
    init() {
        /*if let bundleID = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: bundleID)
                }
     */
        // 캡쳐 실행 단축키
        KeyboardShortcuts.onKeyDown(for: .captureExecution) {
            CaptureWindowManager.shared.show()
            // 캡처 창도 활성화되어야 하므로 포커스 가져오기
            NSApp.activate(ignoringOtherApps: true)
        }
        
        // 설정 창 열기 단축키
        KeyboardShortcuts.onKeyDown(for: .openSettings) {
            CaptureWindowManager.shared.showSettings()
            // 설정 창을 맨 앞으로 강제로 끌어오고 포커스 주기
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        MenuBarExtra("Smart Capture", systemImage: "viewfinder.circle") {
            Button("설정 창 열기") {
                CaptureWindowManager.shared.showSettings()
                // 상단바에서 눌렀을 때도 맨 앞으로 가져오기
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
