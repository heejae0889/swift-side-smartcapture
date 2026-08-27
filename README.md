# SmartCapture (스마트 캡처)

**SmartCapture**는 화면을 캡처하는 즉시 해당 이미지의 내용을 자동으로 분석하고 설명해 주는 macOS용 유틸리티 앱입니다. 

번거로운 추가 조작 없이 캡처만 하면 상황에 맞는 설명을 생성하며, 사용자가 미리 원하는 문구(프롬프트)를 지정해 두어 맞춤형 텍스트를 결과물로 받아볼 수도 있습니다.

결과물은 작업을 원활히 이어갈 수 있도록 화면에 팝업되며 팝업 위치와 크기는 설정에서 바꿀 수 있습니다.

<br>

## 주요 기능 (Features)

*   **자동 이미지 분석 (Auto-Captioning):** 캡처한 이미지를 즉각적으로 분석하여, 이미지 내 객체나 상황에 대한 텍스트 설명을 자동으로 생성합니다.
*   **사전 설정 문구 적용 (Custom Prompts):** 사용자가 미리 설정해 둔 문구나 지시어에 맞춰 이미지 분석 결과를 원하는 형태나 포맷으로 출력할 수 있습니다.
*   **백그라운드 자동화 (Zero-Click Workflow):** 캡처 후 별도의 변환 버튼을 누르거나 프로그램을 조작할 필요 없이 백그라운드에서 매끄럽게 동작합니다.
*   **ai모델 선택 (Ai-model selection):** 기호에 맞는 ai 모델을 선택하여 이용할 수 있습니다.

<br>

## 기술 스택 (Tech Stack)

*   **Language:** Swift
*   **Framework:** SwiftUI
*   **Platform:** macOS
*   **IDE:** Xcode

<br>

## 설치 및 실행 방법 (Getting Started)

1. 이 저장소를 로컬 맥(Mac)으로 클론(Clone)하거나 다운로드합니다.
   ```bash
   git clone [https://github.com/본인아이디/SmartCapture.git](https://github.com/본인아이디/SmartCapture.git)

2. Xcode에서 SmartCapture.xcodeproj 파일을 실행합니다.

3. 상단 메뉴에서 Product > Run을 클릭하거나 단축키 Command(⌘) + R을 눌러 앱을 빌드하고 실행합니다.

4. 본인의 최상단의 아이콘을 누르거나 option+o 를 통해 설정창으로 이동합니다.

5. 본인의 gemini api key를 발급받아 입력한 후 이용할 수 있습니다.
