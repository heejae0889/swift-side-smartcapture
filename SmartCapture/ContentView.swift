import SwiftUI
import KeyboardShortcuts
import Combine
import MarkdownUI

class ResultViewModel: ObservableObject {
    @Published var answer: String = ""
    @Published var isLoading: Bool = false
}

struct ContentView: View {
    @AppStorage("isPresetMode") private var isPresetMode = false
    @AppStorage("presetText") private var presetText = "이 내용을 한국어로 요약해줘"
    @AppStorage("popupPosition") private var popupPosition = 1
    @State private var  userAPIKey = ""
    @AppStorage("selectedModel") private var selectedModel = "gemini-3.5-flash-lite"

    var body: some View {
        Form {
            Section(header: Text("")) {
                SecureField("API 키를 입력하세요", text: $userAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .onAppear {
                                        // 뷰가 나타날 때 키체인에서 키를 불러옴
                                        if let savedKey = KeychainHelper.shared.read() {
                                            userAPIKey = savedKey
                                        }
                                    }
                                    .onChange(of: userAPIKey) {_, newValue in
                                        // 값이 변경될 때마다 키체인에 암호화 저장
                                        KeychainHelper.shared.save(newValue)
                                    }
                
                HStack {
                    Text("API 키가 없으신가요?")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Link("무료로 발급받기", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, -10)
                Picker("AI 선택:", selection: $selectedModel) {
                        Text("Gemini Flash-Lite (빠른 속도, 보통 지능)").tag("gemini-3.5-flash-lite")
                        Text("Gemini Flash (중간 속도, 준수한 지능)").tag("gemini-3.6-flash")
                        Text("Gemini Pro (느린 속도, 고지능)").tag("gemini-3.1-pro-preview")
                        
                }
                .padding(.top, 5)
            }

            Section(header: Text("")) {
                KeyboardShortcuts.Recorder("캡쳐 실행 단축키:", name: .captureExecution)
                KeyboardShortcuts.Recorder("설정 창 열기 단축키:", name: .openSettings)
            }
            .padding(.top, 2)
            Section(header: Text("")) {
                Picker("결과창 위치:", selection: $popupPosition) {
                    Text("마우스 주변").tag(1)
                    Text("화면 우측 상단").tag(2)
                    Text("화면 우측 하단").tag(3)
                    Text("화면 좌측 상단").tag(4)
                    Text("화면 좌측 하단").tag(5)
                }
            }
            .padding(.top, 2)
            
            Section(header: Text("")) {
                Toggle("미리 설정한 문구 사용", isOn: $isPresetMode)
                
                if isPresetMode {
                    VStack(alignment: .leading) {
                        Text("프리셋 질문:")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextEditor(text: $presetText)
                            .frame(height: 60)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                    }
                } else {
                    Text("")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
        }
        .padding()
        .frame(width: 400, height: 450,alignment: .top)
        
        .overlay(
                    Text(verbatim: "heejae6999@gmail.com") // 내가 만듦
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.leading, 15)
                        .padding(.bottom, 10),
                    alignment: .bottomLeading
                )
    }
}

struct CaptureOverlayView: View {
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            if isDragging {
                Rectangle()
                    .fill(Color.black)
                    .blendMode(.destinationOut)
                    .frame(width: abs(currentPoint.x - startPoint.x),
                           height: abs(currentPoint.y - startPoint.y))
                    .position(x: (startPoint.x + currentPoint.x) / 2,
                              y: (startPoint.y + currentPoint.y) / 2)
                
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: abs(currentPoint.x - startPoint.x),
                           height: abs(currentPoint.y - startPoint.y))
                    .position(x: (startPoint.x + currentPoint.x) / 2,
                              y: (startPoint.y + currentPoint.y) / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        startPoint = value.startLocation
                        isDragging = true
                    }
                    currentPoint = value.location
                }
                .onEnded { value in
                    isDragging = false
                    
                    let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                    
                    if distance < 5 {
                        print(" 클릭됨")
                        CaptureWindowManager.shared.cancelAll()
                    } else {
                        print("영역 선택됨, 좌표: \(startPoint) ~ \(currentPoint)")
                        CaptureWindowManager.shared.captureArea(start: startPoint, end: currentPoint)
                    }
                }
        )
        .edgesIgnoringSafeArea(.all)
    }
}


// 입력창 한 줄(라인) 개수에 따른 실제 픽셀 높이를 계산.
// FloatingInputView와 CaptureWindowManager가 동일한 기준으로 높이를 맞추기 위해 공용으로 사용.
let inputFieldFont = NSFont.systemFont(ofSize: 14)

func calculateInputPanelHeight(forLines lines: Int) -> CGFloat {
    let lineHeight = ceil(inputFieldFont.ascender - inputFieldFont.descender + inputFieldFont.leading)
    let textContainerVerticalInset: CGFloat = 12   // GrowingTextView의 textContainerInset 상하 합(6+6)
    // 주의: 바깥쪽 .padding(5) 여백은 FloatingInputView의 .frame(height: textHeight + 10)에서 별도로 더해지므로
    // 여기서는 절대 중복으로 더하면 안 됨 (더하면 GrowingTextView 자체 높이가 실제 글자보다 커져서
    // 세로 중앙 정렬용 여백 계산이 어긋나고 커서 위치가 밀림)
    return ceil(CGFloat(lines) * lineHeight) + textContainerVerticalInset
}

// 줄바꿈이 되는 순간부터 실제 내용물 높이(usedRect)를 그대로 알려주는 오토그로우 텍스트뷰.
// maxHeight를 넘어서면 스스로 커지는 대신 NSScrollView가 세로 스크롤을 담당한다.
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = inputFieldFont
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.textColor = .labelColor
        textView.typingAttributes = [.font: inputFieldFont, .foregroundColor: NSColor.labelColor]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false   // 6줄을 넘길 때만 명시적으로 켠다 (불필요한 깜빡임 방지)
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .automatic

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // 창이 뜨자마자 바로 타이핑할 수 있도록 포커스 이동
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textView.window?.makeFirstResponder(textView)
        }

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            textView.typingAttributes = [.font: inputFieldFont, .foregroundColor: NSColor.labelColor]
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.font, value: inputFieldFont, range: NSRange(location: 0, length: storage.length))
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: storage.length))
            }
        }
        context.coordinator.recalculateHeight()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            enforceFont(on: tv)
            parent.text = tv.string
            recalculateHeight()
        }

        // 타이핑/한글 조합 중에 폰트가 시스템 기본값으로 슬쩍 바뀌는 것을 막기 위해
        // 매번 전체 텍스트에 강제로 같은 폰트를 다시 씌워준다.
        private func enforceFont(on tv: NSTextView) {
            tv.typingAttributes = [.font: inputFieldFont, .foregroundColor: NSColor.labelColor]
            if let storage = tv.textStorage, storage.length > 0 {
                storage.addAttribute(.font, value: inputFieldFont, range: NSRange(location: 0, length: storage.length))
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: storage.length))
            }
        }

        // 엔터: 전송 / Shift+엔터: 줄바꿈
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }

        func recalculateHeight() {
            guard let tv = textView, let layoutManager = tv.layoutManager, let container = tv.textContainer, let scrollView = scrollView else { return }
            layoutManager.ensureLayout(for: container)

            let baseInset: CGFloat = 6 // 위/아래 기본 여백
            let pureTextHeight = layoutManager.usedRect(for: container).height
            let contentHeight = pureTextHeight + baseInset * 2
            let newHeight = min(max(contentHeight, parent.minHeight), parent.maxHeight)

            // 박스가 실제 글자보다 넉넉해서(=minHeight로 눌려서) 남는 여백은
            // 위/아래에 똑같이 나눠줘서 텍스트가 세로 중앙에 오도록 함
            let leftover = max(0, newHeight - contentHeight)
            let verticalInset = baseInset + leftover / 2
            if abs(tv.textContainerInset.height - verticalInset) > 0.5 {
                tv.textContainerInset = NSSize(width: 4, height: verticalInset)
            }

            if abs(parent.dynamicHeight - newHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = newHeight
                }
            }

            // 6줄(=maxHeight)을 실제로 넘어갈 때만 스크롤바 표시
            let needsScroll = contentHeight > parent.maxHeight + 0.5
            if scrollView.hasVerticalScroller != needsScroll {
                scrollView.hasVerticalScroller = needsScroll
            }
        }
    }
}

struct FloatingInputView: View {
    @State private var inputText: String = ""
    @State private var textHeight: CGFloat

    var panelWidth: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onSubmit: (String) -> Void
    var onHeightChange: (CGFloat) -> Void

    init(panelWidth: CGFloat, minHeight: CGFloat, maxHeight: CGFloat, onSubmit: @escaping (String) -> Void, onHeightChange: @escaping (CGFloat) -> Void) {
        self.panelWidth = panelWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.onSubmit = onSubmit
        self.onHeightChange = onHeightChange
        _textHeight = State(initialValue: minHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if inputText.isEmpty {
                Text("AI에게 물어보기...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.leading, 9)   // NSTextView의 textContainerInset(4) + lineFragmentPadding(5) 기본값과 동일
                    .padding(.top, 6)       // GrowingTextView의 기본 baseInset(6)과 동일
                    .allowsHitTesting(false)
            }
            GrowingTextView(text: $inputText, dynamicHeight: $textHeight, minHeight: minHeight, maxHeight: maxHeight) {
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSubmit(inputText)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
        .padding(5)
        .frame(width: panelWidth, height: textHeight + 10) // 5+5 outer padding 포함
        .onChange(of: textHeight) { _, newValue in
            onHeightChange(newValue + 10)
        }
        .onAppear {
            onHeightChange(minHeight + 10)
        }
    }
}

struct ResultView: View {
    @ObservedObject var viewModel: ResultViewModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 분석 결과", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.blue)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            if viewModel.isLoading {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text(viewModel.answer)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                MathWebView(text: viewModel.answer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if !viewModel.isLoading {
                HStack {
                    Spacer()
                    Button("복사하기") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.answer, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 15)))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.2)))
        .edgesIgnoringSafeArea(.all)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
