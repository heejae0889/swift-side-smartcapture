import SwiftUI
import KeyboardShortcuts
import Combine
import MarkdownUI

class ResultViewModel: ObservableObject {
    @Published var priorTranscript: String = ""   // 이전에 완료된 턴들의 질문/답변 기록
    @Published var currentQuestion: String = ""    // 지금 진행 중인 턴의 질문 (후속 질문일 때만 표시, 최초 질문은 기존처럼 숨김)
    @Published var currentAnswer: String = ""      // 지금 진행 중인 턴의 답변(스트리밍 버퍼) / 로딩 문구
    @Published var isLoading: Bool = false
    // isLoading은 첫 글자가 도착하는 순간 false가 되므로, 답변이 실시간으로 나오는 중에는
    // 이어 질문을 막을 수 없음. 요청 시작부터 스트리밍 완료까지 전 구간을 덮는 별도 플래그.
    @Published var isStreaming: Bool = false
    // AI가 답변 끝에 덧붙인 추천 후속 질문. 입력창 플레이스홀더로 사용됨.
    @Published var suggestedQuestion: String = ""

    static let nextMarker = "[[NEXT]]"
    static let nextMarkerEnd = "[[/NEXT]]"

    // 추천 질문 마커부터 뒤쪽을 화면에서 숨김.
    // 스트리밍 중에는 마커가 "[[NE"처럼 일부만 도착할 수 있어, 꼬리에 걸친 조각도 함께 제거해야
    // 토큰이 잠깐 노출되는 것을 막을 수 있음.
    static func stripSuggestion(_ text: String) -> String {
        if let range = text.range(of: nextMarker) {
            return String(text[..<range.lowerBound])
        }
        for length in stride(from: nextMarker.count - 1, through: 1, by: -1) {
            if text.hasSuffix(String(nextMarker.prefix(length))) {
                return String(text.dropLast(length))
            }
        }
        return text
    }

    // 완료된 답변에서 추천 질문을 추출 (없으면 nil)
    static func extractSuggestion(from text: String) -> String? {
        guard let start = text.range(of: nextMarker) else { return nil }
        var tail = String(text[start.upperBound...])
        if let end = tail.range(of: nextMarkerEnd) {
            tail = String(tail[..<end.lowerBound])
        }
        let cleaned = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MathWebView에 실제로 넘길 전체 텍스트 (완료된 기록 + 진행 중인 턴)
    // [[TURN_START]]는 후속 질문이 시작되는 지점을 표시하는 마커. WebView가 이 위치로 스크롤함.
    // [[Q]]...[[/Q]]는 사용자 질문 영역 표시. WebView에서 굵고 크게 스타일링됨.
    // (HTML 태그가 아니라 평범한 텍스트 토큰이어야 함 - AI 답변 속 HTML을 전부 이스케이프하면서도
    //  이 마커만은 살려두기 위해서. 예전처럼 <div>를 쓰면 AI가 <script>를 출력했을 때 막을 방법이 없음)
    var displayText: String {
        let answer = ResultViewModel.stripSuggestion(currentAnswer)
        if currentQuestion.isEmpty {
            return priorTranscript + answer
        } else {
            return priorTranscript + "\n\n[[TURN_START]]\n\n---\n\n[[Q]]\(currentQuestion)[[/Q]]\n\n" + answer
        }
    }

    // 클립보드 복사용: 내부 마커를 제거한 깨끗한 텍스트
    var plainTextForCopy: String {
        return displayText
            .replacingOccurrences(of: "[[TURN_START]]", with: "")
            .replacingOccurrences(of: "[[Q]]", with: "Q. ")
            .replacingOccurrences(of: "[[/Q]]", with: "")
    }
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
    var autoFocus: Bool = true   // 캡쳐 직후 질문창은 바로 입력 가능해야 하지만, 결과창의 이어 질문란은 포커스를 뺏으면 안 됨
    var isEnabled: Bool = true   // 답변 생성 중에는 입력을 막기 위함
    var tabSuggestion: String = "" // 빈 상태에서 탭을 누르면 채워질 추천 질문
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
        textView.isEditable = isEnabled
        textView.isSelectable = true

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
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textView.window?.makeFirstResponder(textView)
            }
        }

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 코디네이터가 들고 있는 parent를 최신 값으로 갱신하지 않으면
        // 높이 재계산이 생성 시점의 오래된 값(minHeight/maxHeight 등)으로 이뤄짐
        context.coordinator.parent = self

        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            textView.typingAttributes = [.font: inputFieldFont, .foregroundColor: NSColor.labelColor]
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.font, value: inputFieldFont, range: NSRange(location: 0, length: storage.length))
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: storage.length))
            }
        }
        if textView.isEditable != isEnabled {
            textView.isEditable = isEnabled
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

            // 아무것도 입력하지 않은 상태에서 탭을 누르면 추천 질문을 그대로 채워넣음.
            // 입력 중이거나 추천이 없으면 false를 반환해 기본 탭 동작(포커스 이동)을 유지.
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                let suggestion = parent.tabSuggestion
                guard textView.string.isEmpty, !suggestion.isEmpty else { return false }

                textView.string = suggestion
                parent.text = suggestion
                enforceFont(on: textView)
                // 커서를 맨 뒤로 보내 바로 이어서 수정할 수 있게 함
                textView.setSelectedRange(NSRange(location: (suggestion as NSString).length, length: 0))
                recalculateHeight()
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
    @State private var followUpText: String = ""
    @State private var followUpHeight: CGFloat = calculateInputPanelHeight(forLines: 1)
    @State private var didCopy: Bool = false
    var onDismiss: () -> Void
    var onAskFollowUp: (String) -> Void

    // 처음 질문창과 동일한 기준: 1줄에서 시작해 6줄까지 늘어나고, 그 이후로는 스크롤
    private var followUpMinHeight: CGFloat { calculateInputPanelHeight(forLines: 1) }
    private var followUpMaxHeight: CGFloat { calculateInputPanelHeight(forLines: 6) }

    // 추천 질문이 있으면 그걸 힌트로 보여주고, 없으면 기본 문구
    private var placeholderText: String {
        if viewModel.isStreaming { return "답변을 생성하는 중입니다..." }
        if !viewModel.suggestedQuestion.isEmpty {
            // 탭으로 채울 수 있다는 것을 알 방법이 없으므로 안내를 덧붙임
            return "\(viewModel.suggestedQuestion)"
        }
        return "이어서 질문하기..."
    }

    var body: some View {
        // 간격을 0으로 두고 각 요소에 필요한 여백만 직접 지정.
        // (기본 간격에 음수 여백을 더해 조정하면 구분선이 답변 영역을 덮어써서
        //  본문이 복사 버튼 위로 겹쳐 보이는 문제가 생김)
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 12)
            // 최초 질문(보여줄 내용이 아직 없음)일 때만 스피너로 전체를 대체하고,
            // 후속 질문일 때는 이전 대화를 그대로 유지한 채 하단에 "분석 중..."이 붙도록 함.
            // (여기서 뷰를 통째로 교체하면 WebView가 새로 만들어지면서 스크롤 위치도 초기화됨)
            if viewModel.isLoading && viewModel.priorTranscript.isEmpty {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text(viewModel.currentAnswer)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                MathWebView(text: viewModel.displayText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 복사 버튼을 별도 행으로 두면 그만큼 답변 영역이 줄어들고 회색 배경도 눈에 띄므로,
                    // 배경 없는 버튼을 답변 영역 위에 겹쳐서 표시함
                    .overlay(alignment: .bottomTrailing) {
                        if !viewModel.isLoading {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(viewModel.plainTextForCopy, forType: .string)
                                // 체크 아이콘이 살짝 튕기듯 나타나도록 스프링 적용
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { didCopy = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                        .scaleEffect(didCopy ? 1.15 : 1.0)
                                    Text(didCopy ? "복사됨" : "복사하기")
                                }
                                .font(.caption)
                                .foregroundColor(didCopy ? .green : .secondary)
                                // 두 문구의 너비가 달라 버튼이 덜컥거리는 것을 막기 위해 최소 너비 고정
                                .frame(minWidth: 62, alignment: .trailing)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .help("답변 전체를 클립보드에 복사")
                            .padding(.trailing, 4)
                            .padding(.bottom, 2)
                        }
                    }
            }

            // 답변 영역은 구분선까지 꽉 차게(위 여백 0), 구분선과 입력창 사이는
            // 아래쪽 컨테이너 여백(16)과 같은 값을 줘서 입력창 위아래 공백을 맞춤
            Divider()
                .padding(.bottom, 16)
            HStack(alignment: .bottom, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if followUpText.isEmpty {
                        Text(placeholderText)
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.7))
                            .padding(.leading, 9)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                    GrowingTextView(
                        text: $followUpText,
                        dynamicHeight: $followUpHeight,
                        minHeight: followUpMinHeight,
                        maxHeight: followUpMaxHeight,
                        autoFocus: false,          // 결과창이 뜰 때 포커스를 뺏지 않도록
                        isEnabled: !viewModel.isStreaming,
                        tabSuggestion: viewModel.suggestedQuestion
                    ) {
                        submitFollowUp()
                    }
                }
                .frame(height: followUpHeight)
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))

                Button("전송") {
                    submitFollowUp()
                }
                .controlSize(.small)
                .disabled(viewModel.isStreaming || followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 15)))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.2)))
        .edgesIgnoringSafeArea(.all)
    }

    private func submitFollowUp() {
        guard !viewModel.isStreaming else { return }
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpText = ""
        followUpHeight = followUpMinHeight // 전송 후 입력창을 다시 1줄 높이로 되돌림
        onAskFollowUp(text)
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
