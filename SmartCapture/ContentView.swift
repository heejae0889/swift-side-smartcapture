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


struct FloatingInputView: View {
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool // 포커스 강제 제어

    /// 창(NSPanel)의 실제 콘텐츠 크기. CaptureWindowManager가 창을 애니메이션으로
    /// 리사이즈할 때 window frame 변화에 맞춰 흘러들어온다.
    var panelSize: CGSize

    var onSubmit: (String) -> Void
    /// 텍스트 길이에 따라 콘텐츠 크기가 바뀔 때마다 호출됨.
    /// CaptureWindowManager가 이 값을 받아 실제 NSPanel의 frame을 애니메이션으로 리사이즈한다.
    var onResize: (CGSize) -> Void = { _ in }

    // MARK: - 크기 계산 상수
    private let minWidth: CGFloat = 250
    private let maxWidth: CGFloat = 420
    private let baseHeight: CGFloat = 45
    private let maxHeight: CGFloat = 260
    private let font = NSFont.systemFont(ofSize: 13)
    private let horizontalPadding: CGFloat = 34 // TextField 내부 padding(8*2) + 바깥 padding(5*2) + 여유
    private let verticalPadding: CGFloat = 29   // 줄바꿈 시 위아래 padding 여유

    /// 아직 "가로로만 늘어나는 중"인 1단계인지 여부.
    /// 이 단계에서는 TextField를 fixedSize(가로)로 그려서 컨테이너 폭에 눌려
    /// 줄바꿈되지 않게 하고, 바깥에서 clipped()로 잘라 보여준다.
    /// -> 창 리사이즈 애니메이션의 "중간 프레임"에도 텍스트 자체는 항상 완전한
    ///    한 줄 형태로 존재하므로, 좁은 폭 기준 줄바꿈으로 텍스트가 사라지는 현상이 없다.
    private var isSingleLinePhase: Bool {
        let displayText = inputText.isEmpty ? " " : inputText
        let singleLineWidth = (displayText as NSString)
            .size(withAttributes: [.font: font])
            .width
        return singleLineWidth <= (maxWidth - horizontalPadding)
    }

    var body: some View {
        HStack(alignment: .top) {
            Group {
                if isSingleLinePhase {
                    TextField("AI에게 물어보기...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false) // 실제 필요한 폭만큼 항상 한 줄로 그림 (컨테이너 폭에 안 눌림)
                } else {
                    TextField("AI에게 물어보기...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .lineLimit(1...12)
                        .fixedSize(horizontal: false, vertical: true) // 실제 필요한 줄바꿈 높이만큼 자유롭게 늘어남
                }
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
            .onSubmit {
                let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onSubmit(inputText)
                }
            }
        }
        .padding(5)
        // panelSize를 그대로 따라감 (SwiftUI 쪽 별도 애니메이션은 걸지 않음 —
        // 실제 창 리사이즈 애니메이션이 매 프레임 panelSize를 갱신해준다).
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .clipped() // 애니메이션 중간 프레임에서 콘텐츠가 컨테이너보다 커도 삐져나오지 않고 항상 깔끔히 잘려 보임
        .onAppear {
            // 창 뜨고 자동으로 클릭
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: inputText) { _, newValue in
            let newSize = calculateSize(for: newValue)
            guard newSize != panelSize else { return }
            onResize(newSize)
        }
    }

    /// 1) 너비가 maxWidth 이내면 텍스트 폭만큼 너비를 늘린다 (높이 고정)
    /// 2) 너비가 maxWidth를 넘으면 그때부터는 너비를 고정하고 줄바꿈된 실제 텍스트 높이만큼 높이를 늘린다
    private func calculateSize(for text: String) -> CGSize {
        let displayText = text.isEmpty ? " " : text
        let contentMaxWidth = maxWidth - horizontalPadding

        let singleLineWidth = (displayText as NSString)
            .size(withAttributes: [.font: font])
            .width

        if singleLineWidth <= contentMaxWidth {
            let targetWidth = max(minWidth, ceil(singleLineWidth + horizontalPadding))
            return CGSize(width: targetWidth, height: baseHeight)
        } else {
            let boundingRect = (displayText as NSString).boundingRect(
                with: CGSize(width: contentMaxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            let targetHeight = ceil(boundingRect.height) + verticalPadding
            return CGSize(width: maxWidth, height: min(maxHeight, max(baseHeight, targetHeight)))
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
