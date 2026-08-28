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
    @AppStorage("userAPIKey") private var userAPIKey = ""
    @AppStorage("selectedModel") private var selectedModel = "gemini-3.5-flash-lite"

    var body: some View {
        Form {
            Section(header: Text("")) {
                SecureField("API 키를 입력하세요", text: $userAPIKey)
                    .textFieldStyle(.roundedBorder)
                
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
                    Text("마우스 포인터 주변 (스마트 조절)").tag(1)
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
    
    var onSubmit: (String) -> Void

    var body: some View {
        HStack {
            TextField("AI에게 물어보기...", text: $inputText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                .onSubmit {
                    if !inputText.isEmpty {
                        onSubmit(inputText)
                    }
                }
        }
        .padding(5)
        .frame(width: 250, height: 45)
        .onAppear {
            // 창 뜨고 자동으로 클릭
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
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
