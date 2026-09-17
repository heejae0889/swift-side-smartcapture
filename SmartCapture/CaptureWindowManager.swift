import SwiftUI
import AppKit
import QuartzCore
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
// 캡쳐 오버레이 전용 호스팅 뷰: resetCursorRects를 오버라이드해서
// "이 뷰 전체는 항상 십자가 커서"라고 AppKit에 등록해둠.
// 이렇게 안 하고 그냥 NSCursor.set()만 하면, 마우스가 움직이는 순간
// AppKit이 커서 영역을 다시 계산하면서 원래 커서로 되돌려버림.
final class CrosshairHostingView: NSHostingView<CaptureOverlayView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        // 영역 선택 중일 때만 십자가 커서 영역을 등록
        // (질문 입력창이 떠 있는 동안에는 등록하지 않아서 일반 커서가 정상 동작하도록)
        guard CaptureWindowManager.shared.shouldForceCrosshair else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }
}

class CaptureWindowManager {
    private var settingsWindow: NSWindow?
    static let shared = CaptureWindowManager()

    // 입력창과 답변창의 너비를 동일하게 맞추기 위한 공용 상수
    private let panelWidth: CGFloat = 400

    private var overlayWindow: NSWindow?
    private var overlayHostingView: NSView?
    private var cursorMonitor: Any?
    private var inputPanel: NSPanel?
    private var resultPanel: NSPanel?
    
    private var resultViewModel = ResultViewModel()
    var lastCapturedImageBase64: String?
    // Gemini API에 보낼 멀티턴 대화 기록 (role: user/model 턴이 계속 쌓임). 새 캡쳐 시작 시 초기화됨.
    private var conversationContents: [[String: Any]] = []

    // 진행 중인 API 요청. 창을 닫거나 새로 캡쳐하면 취소해야 함.
    private var currentRequestTask: Task<Void, Never>?
    // 요청 세대 번호. 취소가 즉시 전파되지 않는 경우에도, 이미 무효가 된 요청이
    // 새 대화에 결과를 써넣지 못하도록 막는 안전장치.
    private var requestGeneration: Int = 0

    // 진행 중인 요청을 취소하고 세대 번호를 올려서, 뒤늦게 도착하는 응답을 전부 무효화함
    private func cancelInFlightRequest() {
        self.currentRequestTask?.cancel()
        self.currentRequestTask = nil
        self.requestGeneration += 1
    }

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
        self.cancelInFlightRequest()
        self.hide()
        self.inputPanel?.close()
        self.resultPanel?.close()
        self.resultPanel = nil
        self.conversationContents = []
        self.resultViewModel.priorTranscript = ""
        self.resultViewModel.currentQuestion = ""
        self.resultViewModel.currentAnswer = ""
        self.resultViewModel.isStreaming = false
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
                    // 그냥 NSCursor.set()은 마우스가 조금만 움직여도 AppKit이 커서 영역을
                    // 다시 계산하면서 원래 커서로 되돌려버림 -> resetCursorRects를 오버라이드해서
                    // "이 뷰 전체는 항상 십자가 커서"라고 아예 등록해버림
                    let hostingView = CrosshairHostingView(rootView: CaptureOverlayView())
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
                    // NSWindow는 기본값이 false라서, 이걸 켜주지 않으면 .mouseMoved 이벤트가
                    // 아예 생성되지 않음 -> 커서 재적용 모니터가 드래그 중에만 동작하게 됨
                    window.acceptsMouseMovedEvents = true
                    window.contentView = hostingView
                    self.overlayWindow = window
                    self.overlayHostingView = hostingView
                }
                
                if let screen = NSScreen.main {
                    self.overlayWindow?.setFrame(screen.frame, display: true)
                }
                // makeKeyAndOrderFront 대신 orderFrontRegardless 사용
                self.overlayWindow?.orderFrontRegardless()

                // 커서는 오버레이가 "실제로 화면에 뜬 뒤"에만 건드림.
                // show() 호출 직후 NSApp.activate()가 겹치면서 앱이 잠깐 비활성/활성을 오가면
                // didResignActiveNotification -> hide()가 끼어들어 커서 설정이 씹히거나
                // 오버레이 없이 커서만 십자가로 남는 문제가 있었음. 다음 런루프 틱까지 미루고
                // 그때도 여전히 보이는 상태인지 확인해서, 그 경우에만 커서를 적용함.
                DispatchQueue.main.async {
                    guard self.shouldForceCrosshair else { return }

                    if let window = self.overlayWindow, let view = self.overlayHostingView {
                        window.invalidateCursorRects(for: view)
                    }
                    NSCursor.crosshair.set()

                    for delay in [0.02, 0.05, 0.1, 0.2] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            guard self.shouldForceCrosshair else { return }
                            NSCursor.crosshair.set()
                        }
                    }

                    // cursor rect만으로는 nonactivatingPanel에서 제대로 안 먹히는 경우가 있어서,
                    // 마우스가 움직이거나 드래그되는 매 순간마다 강제로 십자가 커서를 다시 적용함
                    // (영역 선택 중일 때만 재적용 - 질문창이 뜬 뒤나 오버레이가 사라진 뒤엔 건드리지 않음)
                    if self.cursorMonitor == nil {
                        self.cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
                            if self.shouldForceCrosshair {
                                NSCursor.crosshair.set()
                            }
                            return event
                        }
                    }
                }
            }
        }
    
    // 십자가 커서를 강제해야 하는 상황인지 판단.
    // 주의: showInputPanel()은 오버레이를 숨기지 않고 addChildWindow로 그 위에 질문창을 얹기 때문에,
    // 영역 선택이 끝난 뒤에도 overlayWindow는 계속 isVisible == true 상태임.
    // 그래서 오버레이 가시성만 보고 판단하면 질문 입력창 위에서도 커서가 십자가로 고정되어
    // 텍스트 커서(I-beam)가 안 뜨는 문제가 생김 -> 질문창이 떠 있으면 강제하지 않음.
    var shouldForceCrosshair: Bool {
        return self.overlayWindow?.isVisible == true && self.inputPanel?.isVisible != true
    }

    func hide() {
        self.overlayWindow?.orderOut(nil)
        if let monitor = self.cursorMonitor {
            NSEvent.removeMonitor(monitor)
            self.cursorMonitor = nil
        }
        NSCursor.arrow.set() // 캡쳐 종료 시 커서를 기본 화살표로 복원
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
                
                await MainActor.run {
                    // 새 캡쳐가 시작되면 이전 대화 문맥은 버리고 새 대화 스레드로 시작.
                    // 아직 응답이 오고 있는 이전 요청이 있으면 반드시 취소해야 함
                    // (안 그러면 그 답변이 나중에 도착해서 새 대화에 섞여 들어감)
                    self.cancelInFlightRequest()
                    self.conversationContents = []
                    self.resultViewModel.priorTranscript = ""
                    self.resultViewModel.currentQuestion = ""
                    self.resultViewModel.currentAnswer = ""
                    self.resultViewModel.isStreaming = false
                    self.resultPanel?.close()
                    self.resultPanel = nil
                    self.handleNextStep()
                }
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

                // 1줄일 때와 6줄일 때의 높이를 미리 계산해둔다 (그 이후로는 스크롤 처리)
                let minHeight = calculateInputPanelHeight(forLines: 1)
                let maxHeight = calculateInputPanelHeight(forLines: 6)

                let rect = self.getPanelRect(width: self.panelWidth, height: minHeight + 10)
                let inputView = FloatingInputView(
                    panelWidth: self.panelWidth,
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    onSubmit: { text in
                        self.inputPanel?.orderOut(nil)
                        self.askGemini(userPrompt: text)
                    },
                    onHeightChange: { newHeight in
                        self.resizeInputPanel(toHeight: newHeight)
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
                panel.contentView = NSHostingView(rootView: inputView)
                self.inputPanel = panel
                if let parent = self.overlayWindow {
                    parent.addChildWindow(panel, ordered: .above)
                }
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)

                // 질문창이 떴으면 영역 선택이 끝난 것이므로 십자가 커서를 해제하고,
                // 오버레이의 커서 영역도 다시 계산시켜서 텍스트 커서가 정상 동작하도록 함
                NSCursor.arrow.set()
                if let overlay = self.overlayWindow, let view = self.overlayHostingView {
                    overlay.invalidateCursorRects(for: view)
                }
            }
        }
    
    // 질문창 높이가 바뀔 때 호출됨.
    // getPanelRect가 설정된 위치(mode)에 따라 위/아래 중 어느 쪽 모서리를 고정할지
    // 이미 계산해주므로, 여기서는 새 높이로 다시 rect를 구해서 반영만 하면 된다.
    // - 화면 우측/좌측 "상단"(mode 2, 4): 위쪽 모서리 고정 → 아래로 늘어남
    // - 화면 우측/좌측 "하단"(mode 3, 5): 아래쪽 모서리 고정 → 위로 늘어남
    private func resizeInputPanel(toHeight newHeight: CGFloat) {
        guard let panel = self.inputPanel else { return }
        let newRect = self.getPanelRect(width: self.panelWidth, height: newHeight)
        if abs(panel.frame.height - newRect.height) < 0.5 && abs(panel.frame.origin.y - newRect.origin.y) < 0.5 {
            return
        }
        // 상단 고정 위치(모드 2, 4)는 높이가 늘어날 때 위치(y)와 크기가 동시에 바뀌는데,
        // CATransaction으로 암묵적 레이어 애니메이션을 꺼서 이 변화가 한 번에 반영되도록 함.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(newRect, display: true, animate: false)
        CATransaction.commit()
    }

    func showResultPopup() {
            DispatchQueue.main.async {
                self.hide()
                if self.resultPanel == nil {
                    let rect = self.getPanelRect(width: self.panelWidth, height: 640)
                    let resultView = ResultView(viewModel: self.resultViewModel, onDismiss: {
                        // 답변이 생성되는 도중 창을 닫으면 요청도 같이 취소
                        self.cancelInFlightRequest()
                        self.resultViewModel.isLoading = false
                        self.resultViewModel.isStreaming = false
                        self.resultPanel?.orderOut(nil)
                        self.resultPanel = nil
                    }, onAskFollowUp: { text in
                        self.askGemini(userPrompt: text)
                    })

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
                    self.resultViewModel.isStreaming = false
                    self.resultViewModel.currentQuestion = ""
                    self.resultViewModel.currentAnswer = "⚠️ API 키가 설정되지 않았습니다.\n\n단축키를 눌러 '설정 창'을 연 뒤, 발급받은 Gemini API 키를 먼저 입력해 주세요."
                    self.showResultPopup()
                }
                return
            }

            // 이미 진행 중인 대화가 있으면 후속 질문, 없으면 캡쳐 직후의 최초 질문
            let isFollowUp = !self.conversationContents.isEmpty

            // 사용자의 키(apiKey)를 주소에 넣음
            let urlString =     "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModel):streamGenerateContent?alt=sse&key=\(apiKey)"
            guard let url = URL(string: urlString) else { return }
            // 최초 질문은 캡쳐한 이미지가 반드시 필요하지만, 후속 질문은 이전 대화 맥락만으로 진행
            if !isFollowUp {
                guard self.lastCapturedImageBase64 != nil else { return }
            }

            // 이전 요청이 아직 돌고 있으면 취소하고, 이번 요청의 세대 번호를 확보
            self.cancelInFlightRequest()
            let generation = self.requestGeneration

            DispatchQueue.main.async {
                self.resultViewModel.isLoading = true
                self.resultViewModel.isStreaming = true
                self.resultViewModel.currentQuestion = isFollowUp ? userPrompt : ""
                self.resultViewModel.currentAnswer = "분석 중..."
                self.showResultPopup()
            }

            let systemInstruction = """
            답변 시 다음 규칙을 100% 엄격히 지켜줘:
            1. 전체적인 설명은 마크다운(Markdown) 포맷으로 정리해.
            2. 수학 공식과 수학 기호는 반드시 전문적인 LaTeX 문법을 사용해.
            2-1. [매우 중요] 단, 코드/HTML 태그/파일명/명령어/속성 이름은 수학이 아니므로
                 절대 LaTeX($ 또는 $$)로 감싸지 마. 반드시 마크다운 백틱(`)이나 코드블록(```)을 써.
                 -  잘못된 예: $$ \\text{<script>} $$ 태그를 사용합니다
                 -  올바른 예: `<script>` 태그를 사용합니다
                 -  여러 줄 코드는 ```html 같은 코드블록으로 감싸.
            2-2. LaTeX는 오직 진짜 수식(변수, 연산, 수식 전개)에만 사용해.
            3. [가장 중요] 수식 블록($ 또는 $$) 안에는 절대 일반 한글 텍스트나 설명을 섞어 쓰지 마
               -  잘못된 예: $$ x^2 입니다. 따라서 y^2 $$
               -  올바른 예: $$ x^2 $$ 입니다. 따라서 $$ y^2 $$
            4. 한글 설명과 수식은 완전히 분리해. 수식을 쓰기 전후로 반드시 $ 기호를 닫고 한글을 써.
            5. 여러 줄의 풀이 과정은 $$ 기호로 크게 감싸되, 그 안에 부연 설명(한글)이 필요하면 수식 블록을 끊고 적어.
            6. 너가 이 분야 최고 전문가가 돼서 정확하고 간결하게 설명해.
            7. 수식은 반드시 KaTeX 라이브러리에서 완벽하게 지원하는 기본 문법만 사용해.
            8. \\begin{align} 대신 반드시 \\begin{aligned}를 사용해.
            9. 괄호를 열었으면 반드시 닫고, 수식 블록($ 또는 $$)의 짝을 완벽하게 맞춰서 출력해.
            """

            // 이번 턴의 사용자 파트: 최초 질문에만 이미지를 포함, 후속 질문은 텍스트만
            var newUserParts: [[String: Any]] = [["text": userPrompt]]
            if !isFollowUp, let base64Image = self.lastCapturedImageBase64 {
                newUserParts.append(["inline_data": ["mime_type": "image/png", "data": base64Image]])
            }
            let newUserTurn: [String: Any] = ["role": "user", "parts": newUserParts]

            // 이전까지의 대화 기록 + 이번 질문을 합쳐서 요청 (아직 conversationContents엔 반영 안 함 - 성공했을 때만 반영)
            let requestContents = self.conversationContents + [newUserTurn]

            let body: [String: Any] = [
                "system_instruction": ["parts": [["text": systemInstruction]]],
                "contents": requestContents,
                // thinkingLevel을 minimal로 낮춰서 답변 시작 전 "생각하는" 시간을 최대한 줄임 (체감 속도 개선의 핵심)
                // + maxOutputTokens로 답변 길이를 적당히 제한해 스트리밍이 끝까지 도착하는 총 시간도 단축
                "generationConfig": [
                    "thinkingConfig": ["thinkingLevel": "minimal"],
                    "maxOutputTokens": 2048
                ]
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            // 비동기 Task로 서버 응답을 실시간으로 한 줄씩 읽어옴
            self.currentRequestTask = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    // [중요] URLSession.bytes는 HTTP 400/403 같은 에러 상태에서도 throw하지 않음.
                    // 이때 응답 본문은 SSE가 아니라 에러 JSON이라 "data: " 줄이 하나도 없고,
                    // 그대로 두면 루프가 정상 종료되어 "성공"으로 처리됨 -> 빈 답변이 저장되고
                    // 사용자에겐 아무 안내 없이 백지 창만 보임. 그래서 상태 코드를 먼저 확인함.
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var rawBody = ""
                        for try await line in bytes.lines {
                            rawBody += line
                            if rawBody.count > 8000 { break } // 비정상적으로 큰 본문 방어
                        }
                        let message = Self.friendlyErrorMessage(statusCode: http.statusCode, body: rawBody)
                        await MainActor.run {
                            guard self.requestGeneration == generation else { return }
                            self.showError(message)
                        }
                        return
                    }

                    var isFirstChunk = true
                    var fullAnswerText = ""

                    for try await line in bytes.lines {
                        // 창이 닫혔거나 새 캡쳐가 시작된 경우 즉시 중단
                        if Task.isCancelled { return }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = line.dropFirst(6)
                        guard let data = jsonString.data(using: .utf8) else { continue }
                        
                        if let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data),
                           let textChunk = decoded.candidates.first?.content.parts.first?.text {
                            
                            fullAnswerText += textChunk

                            // 이 요청이 아직 유효한 경우에만 화면에 반영.
                            // 무효해졌다면(false) 루프를 빠져나가 남은 응답을 버림.
                            let shouldClearPlaceholder = isFirstChunk
                            let stillCurrent = await MainActor.run { () -> Bool in
                                guard self.requestGeneration == generation else { return false }
                                if shouldClearPlaceholder {
                                    self.resultViewModel.currentAnswer = ""
                                    self.resultViewModel.isLoading = false
                                }
                                self.resultViewModel.currentAnswer += textChunk
                                return true
                            }
                            if !stillCurrent { return }
                            isFirstChunk = false
                        }
                    }

                    if Task.isCancelled { return }

                    // 상태 코드는 정상인데 실제로 받은 텍스트가 하나도 없는 경우(응답 형식 변경,
                    // 안전 필터로 인한 차단 등). 이때도 빈 답변을 기록으로 남기면 안 됨.
                    if fullAnswerText.isEmpty {
                        await MainActor.run {
                            guard self.requestGeneration == generation else { return }
                            self.showError("답변을 받지 못했습니다.\n\n요청이 차단되었거나 응답이 비어 있습니다. 질문을 바꾸거나 다른 모델로 다시 시도해 주세요.")
                        }
                        return
                    }

                    // 스트리밍 완료: 이번 턴을 대화 기록에 편입시켜 다음 후속 질문에서도 문맥이 이어지도록 함
                    await MainActor.run {
                        // 이미 무효가 된 요청이면 대화 기록에 절대 쓰지 않음
                        // (창을 닫거나 새로 캡쳐한 뒤 뒤늦게 도착한 응답이 새 대화에 섞이는 것을 방지)
                        guard self.requestGeneration == generation else { return }

                        self.conversationContents.append(newUserTurn)
                        self.conversationContents.append(["role": "model", "parts": [["text": fullAnswerText]]])

                        if isFollowUp {
                            self.resultViewModel.priorTranscript += "\n\n[[TURN_START]]\n\n---\n\n**Q.** \(userPrompt)\n\n\(fullAnswerText)"
                        } else {
                            self.resultViewModel.priorTranscript = fullAnswerText
                        }
                        self.resultViewModel.currentQuestion = ""
                        self.resultViewModel.currentAnswer = ""
                        self.resultViewModel.isLoading = false
                        self.resultViewModel.isStreaming = false // 스트리밍 끝 -> 이어 질문 다시 허용
                    }
                } catch {
                    // 사용자가 직접 취소한 경우는 에러가 아니므로 조용히 종료
                    if Task.isCancelled || error is CancellationError { return }
                    await MainActor.run {
                        guard self.requestGeneration == generation else { return }
                        self.showError("통신 에러가 발생했습니다.\n\n인터넷 연결 상태를 확인해 주세요.\n\n(\(error.localizedDescription))")
                    }
                }
            }
        }

    // 모든 에러 표시를 한 곳에서 처리.
    // 이어 질문 중 에러가 나면 이전 대화 바로 뒤에 글이 붙어버리므로 구분선을 넣어주고,
    // 어떤 경로로 실패하든 isStreaming을 반드시 해제해서 입력창이 잠긴 채 남지 않도록 함.
    @MainActor
    private func showError(_ message: String) {
        let separator = self.resultViewModel.priorTranscript.isEmpty ? "" : "\n\n---\n\n"
        self.resultViewModel.currentQuestion = ""
        self.resultViewModel.currentAnswer = separator + "⚠️ " + message
        self.resultViewModel.isLoading = false
        self.resultViewModel.isStreaming = false
    }

    // Gemini 에러 응답을 사용자가 이해할 수 있는 안내문으로 바꿔줌.
    // 에러 본문 형식: {"error": {"code": 400, "message": "...", "status": "INVALID_ARGUMENT"}}
    private static func friendlyErrorMessage(statusCode: Int, body: String) -> String {
        var detail = ""
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            detail = message
        }

        let summary: String
        switch statusCode {
        case 400:
            summary = "요청이 거부되었습니다 (400).\n\nAPI 키 형식이 잘못되었거나, 선택한 모델이 이 요청을 지원하지 않을 수 있습니다. 설정에서 다른 모델을 선택해 보세요."
        case 401, 403:
            summary = "API 키가 유효하지 않습니다 (\(statusCode)).\n\n설정 창에서 키를 다시 확인하고 입력해 주세요."
        case 404:
            summary = "모델을 찾을 수 없습니다 (404).\n\n설정에서 선택한 모델 이름이 더 이상 제공되지 않을 수 있습니다. 다른 모델을 선택해 보세요."
        case 429:
            summary = "사용량 한도를 초과했습니다 (429).\n\n잠시 후 다시 시도하거나, 하루 무료 할당량이 모두 소진되었는지 확인해 주세요."
        case 500, 502, 503, 504:
            summary = "서버에 일시적인 문제가 있습니다 (\(statusCode)).\n\n잠시 후 다시 시도해 주세요."
        default:
            summary = "요청이 실패했습니다 (\(statusCode))."
        }

        return detail.isEmpty ? summary : summary + "\n\n---\n\n상세: \(detail)"
    }
}

extension NSImage {
    func toBase64() -> String? {
        guard let tiff = self.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])?.base64EncodedString()
    }
}
