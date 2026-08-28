import SwiftUI
import AppKit
import ScreenCaptureKit

struct GeminiResponse: Codable, Sendable {
    struct Candidate: Codable, Sendable {
        struct Content: Codable, Sendable {
            struct Part: Codable, Sendable {
                let text: String
            }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }
}

class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }
}

class SettingsWindow: NSWindow{
    override func resignKey() {
        super.resignKey()
        self.close()
    }
}
class CaptureWindowManager {
    private var settingsWindow: NSWindow?
    static let shared = CaptureWindowManager()
    
    private var overlayWindow: NSWindow?
    private var inputPanel: NSPanel?
    private var inputHostingView: NSHostingView<FloatingInputView>?
    private var resultPanel: NSPanel?
    
    private var resultViewModel = ResultViewModel()
    var lastCapturedImageBase64: String?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
            self?.inputPanel?.close()
        }
    }
    
    func cancelAll() {
        self.hide()
        self.inputPanel?.close()
        self.resultPanel?.close()
        self.resultPanel = nil
    }
    func showSettings() {
            DispatchQueue.main.async {
                if self.settingsWindow == nil {
                    let window = SettingsWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
                        styleMask: [.titled, .closable, .miniaturizable],
                        backing: .buffered,
                        defer: false
                    )
                    window.title = "스마트캡쳐 설정"
                    window.center()
                    window.isReleasedWhenClosed = false
                    window.level = .floating
                    window.contentView = NSHostingView(rootView: ContentView())
                    self.settingsWindow = window
                }
                if #available(macOS 14.0, *) {
                    NSApp.activate()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }
                self.settingsWindow?.makeKeyAndOrderFront(nil)
                self.settingsWindow?.orderFrontRegardless()
            }
        }

    func show() {
            DispatchQueue.main.async {
                self.cancelAll()
                
                if self.overlayWindow == nil {
                    let hostingController = NSHostingController(rootView: CaptureOverlayView())
                    let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
                    let window = NSPanel(
                        contentRect: screenRect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false
                    )
                    
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.level = .screenSaver
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    window.ignoresMouseEvents = false // 마우스 이벤트는 무조건 받음
                    window.contentViewController = hostingController
                    self.overlayWindow = window
                }
                
                if let screen = NSScreen.main {
                    self.overlayWindow?.setFrame(screen.frame, display: true)
                }
                // makeKeyAndOrderFront 대신 orderFrontRegardless 사용
                self.overlayWindow?.orderFrontRegardless()
            }
        }
    
    func hide() {
        self.overlayWindow?.orderOut(nil)
    }

    func captureArea(start: CGPoint, end: CGPoint) {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = max(abs(start.x - end.x), 1)
        let height = max(abs(start.y - end.y), 1)
        let captureRect = CGRect(x: x, y: y, width: width, height: height)

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let myAppBundleId = Bundle.main.bundleIdentifier
                let excludedWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == myAppBundleId }
                
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let config = SCStreamConfiguration()
                config.sourceRect = captureRect
                config.width = Int(width) * 2
                config.height = Int(height) * 2
                
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(cgImage: image, size: captureRect.size)
                
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([nsImage])
                
                if let base64 = nsImage.toBase64() {
                    self.lastCapturedImageBase64 = base64
                }
                
                await MainActor.run { self.handleNextStep() }
            } catch { print("캡쳐 에러: \(error)") }
        }
    }
    
    private func handleNextStep() {
        if UserDefaults.standard.bool(forKey: "isPresetMode") {
            let preset = UserDefaults.standard.string(forKey: "presetText") ?? "이 이미지 설명해줘"
            self.askGemini(userPrompt: preset)
        } else {
            self.showInputPanel()
        }
    }

    private func getPanelRect(width: CGFloat, height: CGFloat) -> NSRect {
                let mode = UserDefaults.standard.integer(forKey: "popupPosition")
                guard let screen = NSScreen.main else { return NSRect(x: 100, y: 100, width: width, height: height) }
                let visible = screen.visibleFrame
                let padding: CGFloat = 20
                var x: CGFloat = 0; var y: CGFloat = 0
                
                switch mode {
                case 2: x = visible.maxX - width - padding; y = visible.maxY - height - padding
                case 3: x = visible.maxX - width - padding; y = visible.minY + padding
                case 4: x = visible.minX + padding; y = visible.maxY - height - padding
                case 5: x = visible.minX + padding; y = visible.minY + padding
                default:
                    let mouse = NSEvent.mouseLocation
                    let offset: CGFloat = 12
                    x = mouse.x + offset
                    y = mouse.y - (height / 2)+25
                    if x + width > visible.maxX {
                        x = mouse.x - width - offset
                    }
                    if y < visible.minY { y = visible.minY + padding }
                    if y + height > visible.maxY { y = visible.maxY - height - padding }
                }
                return NSRect(x: x, y: y, width: width, height: height)
            }

    func showInputPanel() {
            DispatchQueue.main.async {
                self.inputPanel?.close()
                
                let initialSize = CGSize(width: 250, height: 45)
                let rect = self.getPanelRect(width: initialSize.width, height: initialSize.height)
                let inputView = FloatingInputView(
                    panelSize: initialSize,
                    onSubmit: { text in
                        self.inputPanel?.orderOut(nil)
                        self.askGemini(userPrompt: text)
                    },
                    onResize: { [weak self] newSize in
                        self?.resizeInputPanel(to: newSize)
                    }
                )
                
                let panel = FocusablePanel(
                    contentRect: rect,
                    styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                
                panel.isFloatingPanel = true
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = true
                panel.titleVisibility = .hidden
                panel.titlebarAppearsTransparent = true
                panel.standardWindowButton(.closeButton)?.isHidden = true
                panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
                panel.standardWindowButton(.zoomButton)?.isHidden = true
                panel.isMovableByWindowBackground = true
                let hostingView = NSHostingView(rootView: inputView)
                panel.contentView = hostingView
                self.inputHostingView = hostingView
                self.inputPanel = panel
                if let parent = self.overlayWindow {
                    parent.addChildWindow(panel, ordered: .above)
                }
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

    /// 질문 입력창의 텍스트 길이에 맞춰 NSPanel 자체의 frame을 부드럽게(탄력있게) 리사이즈한다.
    /// - 너비가 늘어날 때는 오른쪽 가장자리를 고정한 채 왼쪽으로 확장
    /// - 높이가 늘어날 때는 윗쪽 가장자리를 고정한 채 아래로 확장
    ///
    /// 핵심: SwiftUI 콘텐츠(panelSize)는 애니메이션 없이 곧바로 "목표 크기"로 갱신해서
    /// 텍스트가 항상 완성된 모습으로 미리 준비되게 하고, 실제 화면에 보이는 "슬라이드로
    /// 늘어나는" 모션은 오직 NSPanel의 창 프레임 애니메이션(clipped된 창 경계)이 담당한다.
    /// 이렇게 하면 애니메이션 중간의 어떤 프레임에서도 텍스트가 좁은 폭 기준으로
    /// 다시 줄바꿈되어 사라지는 현상이 생기지 않는다.
    private func resizeInputPanel(to newSize: CGSize) {
        guard let panel = self.inputPanel else { return }
        let oldFrame = panel.frame
        guard oldFrame.size != newSize else { return }

        let deltaWidth = newSize.width - oldFrame.size.width
        let deltaHeight = newSize.height - oldFrame.size.height

        var newFrame = oldFrame
        newFrame.size = newSize
        // 오른쪽 고정 -> 왼쪽으로 확장
        newFrame.origin.x -= deltaWidth
        // 위쪽 고정 -> 아래로 확장 (AppKit 좌표계는 y가 아래쪽일수록 작아짐)
        newFrame.origin.y -= deltaHeight

        // SwiftUI 콘텐츠를 즉시 목표 크기로 갱신 (텍스트 레이아웃을 미리 최종 상태로 확정)
        self.inputHostingView?.rootView = FloatingInputView(
            panelSize: newSize,
            onSubmit: { text in
                self.inputPanel?.orderOut(nil)
                self.askGemini(userPrompt: text)
            },
            onResize: { [weak self] size in
                self?.resizeInputPanel(to: size)
            }
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            // back-ease-out 스타일 커브: 목표치를 살짝 넘겼다가 튕기듯 돌아오는 탄력있는 느낌
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        }
    }
    
    func showResultPopup() {
            DispatchQueue.main.async {
                self.hide()
                if self.resultPanel == nil {
                    let rect = self.getPanelRect(width: 400, height: 640)
                    let resultView = ResultView(viewModel: self.resultViewModel) {
                        self.resultPanel?.orderOut(nil)
                        self.resultPanel = nil
                    }

                    let panel = NSPanel(
                        contentRect: rect,
                        styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered,
                        defer: false
                    )
                    
                    panel.isFloatingPanel = true
                    panel.level = .mainMenu
                    
                    panel.backgroundColor = .clear
                    panel.isOpaque = false
                    panel.hasShadow = true
                    
                    panel.titleVisibility = .hidden
                    panel.titlebarAppearsTransparent = true
                    
                    panel.standardWindowButton(.closeButton)?.isHidden = true
                    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    panel.standardWindowButton(.zoomButton)?.isHidden = true
                    
                    panel.isMovableByWindowBackground = true
                    panel.minSize = NSSize(width: 250, height: 200)
                    
                    panel.contentView = NSHostingView(rootView: resultView)
                    self.resultPanel = panel
                    panel.makeKeyAndOrderFront(nil)
                }
            }
        }

    func askGemini(userPrompt: String) {
            let savedKey = KeychainHelper.shared.read() ?? ""
            let apiKey = savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.5-flash-lite"
            // 키가 비어있는지 검사 (키가 없으면 안내 메시지 띄우고 종료)
            guard !apiKey.isEmpty else {
                DispatchQueue.main.async {
                    self.resultViewModel.isLoading = false
                    self.resultViewModel.answer = " API 키가 설정되지 않았습니다.\n\n단축키를 눌러 '설정 창'을 연 뒤, 발급받은 Gemini API 키를 먼저 입력해 주세요."
                    self.showResultPopup()
                }
                return
            }

            // 사용자의 키(apiKey)를 주소에 넣음
            let urlString =     "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModel):streamGenerateContent?alt=sse&key=\(apiKey)"
            guard let url = URL(string: urlString), let base64Image = self.lastCapturedImageBase64 else { return }

            DispatchQueue.main.async {
                self.resultViewModel.isLoading = true
                self.resultViewModel.answer = "분석 중..."
                self.showResultPopup()
            }

            let systemInstruction = """
            답변 시 다음 규칙을 100% 엄격히 지켜줘:
            1. 전체적인 설명은 마크다운(Markdown) 포맷으로 정리해.
            2. 모든 수학 공식과 기호는 반드시 전문적인 LaTeX 문법을 사용해.
            3. [가장 중요] 수식 블록($ 또는 $$) 안에는 절대 일반 한글 텍스트나 설명을 섞어 쓰지 마
               -  잘못된 예: $$ x^2 입니다. 따라서 y^2 $$
               -  올바른 예: $$ x^2 $$ 입니다. 따라서 $$ y^2 $$
            4. 한글 설명과 수식은 완전히 분리해. 수식을 쓰기 전후로 반드시 $ 기호를 닫고 한글을 써.
            5. 여러 줄의 풀이 과정은 $$ 기호로 크게 감싸되, 그 안에 부연 설명(한글)이 필요하면 수식 블록을 끊고 적어.
            6. 너가 이 분야 최고 전문가가 돼서 설명하고 혹시나 모르겠으면 인터넷을 찾아보거나 논문을 찾고해도 좋아.
            7. 수식은 반드시 KaTeX 라이브러리에서 완벽하게 지원하는 기본 문법만 사용해.
            8. \\begin{align} 대신 반드시 \\begin{aligned}를 사용해.
            9. 괄호를 열었으면 반드시 닫고, 수식 블록($ 또는 $$)의 짝을 완벽하게 맞춰서 출력해.
            
            사용자 질문: \(userPrompt)
            """

            let body: [String: Any] = [
                "contents": [[
                    "parts": [
                        ["text": systemInstruction],
                        ["inline_data": ["mime_type": "image/png", "data": base64Image]]
                    ]
                ]]
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            // 비동기 Task로 서버 응답을 실시간으로 한 줄씩 읽어옴
            Task {
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    var isFirstChunk = true

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = line.dropFirst(6)
                        guard let data = jsonString.data(using: .utf8) else { continue }
                        
                        if let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data),
                           let textChunk = decoded.candidates.first?.content.parts.first?.text {
                            
                            await MainActor.run {
                                if isFirstChunk {
                                    self.resultViewModel.answer = ""
                                    self.resultViewModel.isLoading = false
                                    isFirstChunk = false
                                }
                                self.resultViewModel.answer += textChunk
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.resultViewModel.answer = "통신 에러가 발생했습니다.\n\nAPI 키가 정확한지, 인터넷이 연결되어 있는지 확인해 주세요.\n또는 하루 토큰의 개수를 초과했을 수 있습니다."
                        self.resultViewModel.isLoading = false
                    }
                }
            }
        }
}

extension NSImage {
    func toBase64() -> String? {
        guard let tiff = self.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])?.base64EncodedString()
    }
}
