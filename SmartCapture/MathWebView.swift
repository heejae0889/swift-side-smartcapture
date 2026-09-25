import SwiftUI
import WebKit

struct MathWebView: NSViewRepresentable {
    var text: String
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MathWebView
        var isLoaded = false
        
        init(_ parent: MathWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            sendTextToWebView(webView: webView, text: parent.text)
        }
        
        func sendTextToWebView(webView: WKWebView, text: String) {
            guard isLoaded else { return }
            
            let base64Text = text.data(using: .utf8)?.base64EncodedString() ?? ""
            webView.evaluateJavaScript("updateContent('\(base64Text)')", completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/contrib/auto-render.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <style>
                :root { color-scheme: light dark; }
                body {
                    font-family: -apple-system, "SF Pro KR", sans-serif;
                    font-size: 15px;
                    line-height: 1.6;
                    padding: 5px;
                    margin: 0;
                    word-wrap: break-word;
                    color: WindowText;
                }
                /* 스크롤 위치 표시용 마커 - 화면에는 보이지 않음 */
                .turn-start {
                    height: 0;
                    margin: 0;
                    padding: 0;
                }
                /* 이어 질문한 사용자의 질문 - 답변 본문과 구분되도록 굵고 조금 크게 */
                .user-question {
                    display: block;
                    font-size: 1.15em;
                    font-weight: 700;
                    line-height: 1.5;
                    margin: 0 0 14px 0;
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                // 지금까지 렌더링된 "이어 질문" 턴의 개수. 새 턴이 생긴 순간을 감지하는 데 사용.
                let lastTurnCount = 0;
                // 답변이 생성되는 동안 화면을 자동으로 아래로 따라가게 할지 여부.
                // 사용자가 직접 위로 스크롤하면 꺼지고, 다시 맨 아래로 내리면 켜짐.
                let autoFollow = true;

                // --- 스프링(용수철) 기반 부드러운 스크롤 ---
                // 그냥 scrollTo를 쓰면 "빡" 하고 순간이동해서 딱딱한 느낌이 남.
                // 목표 지점을 향해 감쇠 진동으로 다가가게 해서 애플 특유의 부드러운 모션을 냄.
                let springTarget = 0;
                let springVelocity = 0;
                let springAnimating = false;

                function springScrollTo(target) {
                    springTarget = target;
                    if (springAnimating) return; // 이미 돌고 있으면 목표만 갱신 (스트리밍 중 계속 따라감)
                    springAnimating = true;
                    springVelocity = 0; // 새 애니메이션은 항상 정지 상태에서 출발

                    const stiffness = 0.018; // 당기는 힘 (클수록 빠릿함)
                    const damping = 0.90;    // 감쇠 (클수록 관성이 오래 유지되어 더 부드럽게 미끄러짐)
                    // 이 조합이면 약 0.3초에 걸쳐 스르륵 가속했다가 감속하며 멈춤.
                    // (값을 키우면 순식간에 끝나버려서 순간이동처럼 보이므로 주의)

                    function step() {
                        if (!springAnimating) return; // 사용자가 직접 스크롤해서 취소된 경우

                        const current = window.scrollY;
                        const distance = springTarget - current;
                        springVelocity = springVelocity * damping + distance * stiffness;

                        // 충분히 가까워지면 정확히 목표에 붙이고 종료
                        if (Math.abs(distance) < 0.5 && Math.abs(springVelocity) < 0.5) {
                            window.scrollTo(0, springTarget);
                            springVelocity = 0;
                            springAnimating = false;
                            return;
                        }

                        // 유효 범위를 벗어나지 않도록 잘라줌 (범위 밖으로 튀면 덜컥거림)
                        const next = Math.max(0, Math.min(current + springVelocity, maxScroll()));
                        window.scrollTo(0, next);
                        requestAnimationFrame(step);
                    }
                    requestAnimationFrame(step);
                }

                // 사용자가 직접 휠/트랙패드로 스크롤하면 진행 중인 스프링을 즉시 취소해서
                // 애니메이션이 사용자 조작과 싸우지 않도록 함
                function cancelSpring() {
                    springAnimating = false;
                    springVelocity = 0;
                }
                window.addEventListener('wheel', function() {
                    cancelSpring();
                    autoFollow = isNearBottom();
                }, { passive: true });

                function maxScroll() {
                    return Math.max(0, document.body.scrollHeight - window.innerHeight);
                }

                function isNearBottom() {
                    return window.innerHeight + window.scrollY >= document.body.scrollHeight - 40;
                }

                window.addEventListener('scroll', function() {
                    // 스프링 애니메이션이 만들어낸 스크롤은 "사용자 조작"이 아니므로 무시.
                    // (안 그러면 애니메이션 도중 중간 지점에서 autoFollow가 꺼져버림)
                    if (springAnimating) return;
                    autoFollow = isNearBottom();
                });

                // AI 답변에 <script>, <div> 같은 HTML 태그가 텍스트로 포함될 수 있음
                // (예: "HTML에서 자바스크립트는 <script> 태그로 작성합니다" 같은 설명).
                // 이걸 innerHTML에 그대로 넣으면 브라우저가 진짜 태그로 해석해서
                // 뒤따르는 내용을 통째로 삼켜버림 -> 답변이 중간에 끊긴 것처럼 보임.
                //
                // 태그는 반드시 '<'로 시작하므로 '<'만 막아도 태그 생성이 원천 차단됨.
                // '>'까지 건드리면 마크다운 인용문(> 인용) 문법이 깨지고,
                // '&'는 marked가 알아서 올바르게 처리하므로 손대지 않음.
                function escapeHtml(str) {
                    return str.replace(/</g, '&lt;');
                }

                // marked가 raw HTML 토큰을 그대로 통과시키지 않도록 렌더러를 교체.
                // 본문을 미리 이스케이프하는 방식은 코드 영역에서 이중 이스케이프를 일으키므로,
                // 이렇게 "HTML로 인식된 부분만" 골라서 평범한 텍스트로 바꾸는 편이 정확함.
                // marked 버전에 따라 렌더러가 문자열 또는 토큰 객체를 넘겨주므로 둘 다 대응.
                try {
                    marked.use({
                        renderer: {
                            html: function(token) {
                                const raw = (typeof token === 'string')
                                    ? token
                                    : (token && (token.raw || token.text)) || '';
                                return escapeHtml(raw);
                            }
                        }
                    });
                } catch (e) {
                    console.error('marked 렌더러 설정 실패:', e);
                }

                // 수식 블록 안에 이스케이프 안 된 TeX 특수문자(&, %, #)가 있으면
                // KaTeX가 파싱 에러를 내면서 원본 텍스트를 그대로(빨간색으로) 뿜어냄.
                // 렌더링 직전에 자동으로 이스케이프 처리해서 이런 에러를 예방함.
                function sanitizeMath(mathStr) {
                    return mathStr
                        .replace(/(?<!\\\\)&/g, '\\\\&')
                        .replace(/(?<!\\\\)%/g, '\\\\%')
                        .replace(/(?<!\\\\)#/g, '\\\\#');
                }

                async function updateContent(base64Str) {
                    const res = await fetch('data:text/plain;base64,' + base64Str);
                    let rawText = await res.text();
                    
                    // --- 스트리밍 중 열려있는 수식 임시로 닫아주기 ---
                    // 주의: 무조건 닫아버리면, 모델이 본문 중간에 짝 없는 $ 를 하나 흘렸을 때
                    // 거기서부터 문서 끝까지가 통째로 수식으로 인식되어 답변 전체가 깨짐.
                    // 그래서 "열린 위치가 글 끝부분일 때"(= 아직 스트리밍 중일 가능성이 높을 때)만 닫는다.
                    let openDisplay = false;
                    let openInline = false;
                    let openIndex = -1;
                    for (let i = 0; i < rawText.length; i++) {
                        if (rawText.substring(i, i+2) === '$$') {
                            if (!openInline) {
                                openDisplay = !openDisplay;
                                openIndex = openDisplay ? i : -1;
                                i++; // 다음 $ 기호 건너뛰기
                            }
                        } else if (rawText[i] === '$') {
                            if (!openDisplay) {
                                openInline = !openInline;
                                openIndex = openInline ? i : -1;
                            }
                        }
                    }

                    const openedNearEnd = openIndex >= 0 && (rawText.length - openIndex) <= 400;
                    if (openDisplay && openedNearEnd) rawText += '$$';
                    else if (openInline && openedNearEnd) rawText += '$';
                    // --------------------------------------------------------
                    
                    let mathBlocks = [];
                    
                    // 🚨 백슬래시 2개(\\)로 수정된 부분
                    // 수식 블록도 나중에 innerHTML로 들어가므로 여기서 같이 이스케이프함.
                    // KaTeX는 DOM의 textContent를 읽어서 렌더링하는데, 그때 &lt;는 다시 <로
                    // 해석되므로 수식 자체는 정상적으로 그려짐.
                    rawText = rawText.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, function(match) {
                        mathBlocks.push(escapeHtml(sanitizeMath(match)));
                        return 'MATHBLOCK' + (mathBlocks.length - 1) + 'ENDMATH';
                    });
                    
                    // 인라인 수식은 줄바꿈을 넘지 못하게 제한.
                    // ([^$]*? 로 두면 짝 없는 $ 하나가 여러 문단을 통째로 삼켜버림)
                    rawText = rawText.replace(/\\$([^$\\n]+?)\\$/g, function(match) {
                        mathBlocks.push(escapeHtml(sanitizeMath(match)));
                        return 'MATHINLINE' + (mathBlocks.length - 1) + 'ENDMATH';
                    });

                    // 주의: 여기서 본문을 미리 이스케이프하면 안 됨.
                    // marked는 코드 영역(백틱)에 대해서는 '&'를 무조건 다시 인코딩하는
                    // 별도의 이스케이프를 적용하기 때문에, 미리 만든 &lt; 가 &amp;lt; 로 이중
                    // 이스케이프되어 화면에 "&lt;" 라는 글자가 그대로 보이게 됨.
                    // 대신 아래 marked 설정에서 raw HTML 토큰만 골라서 무력화함.
                    
                    // 수식을 자리표시자로 빼낸 뒤, 마크다운 볼드 예외 처리.
                    //
                    // 마크다운 표준(CommonMark)에서는 닫는 ** 앞이 구두점이고 바로 뒤가 문자면
                    // 닫기로 인정하지 않음. 한국어는 "**보호 권한(Permission)**에" 처럼
                    // 괄호로 끝나고 조사가 바로 붙는 경우가 흔해서 별표가 그대로 노출됨.
                    // 이 경우만 골라 미리 빼두었다가 파싱 후 <strong>으로 복원한다.
                    let boldBlocks = [];
                    rawText = rawText.replace(/\\*\\*([^\\n*]*[\\p{P}\\p{S}])\\*\\*(?=[^\\s\\p{P}\\p{S}])/gu, function(match, inner) {
                        boldBlocks.push(escapeHtml(inner));
                        return 'BOLDMARK' + (boldBlocks.length - 1) + 'ENDBOLD';
                    });

                    let parsedHtml = marked.parse(rawText);

                    parsedHtml = parsedHtml.replace(/BOLDMARK(\\d+)ENDBOLD/g, function(match, index) {
                        return '<strong>' + boldBlocks[index] + '</strong>';
                    });
                    
                    // 🚨 여기도 백슬래시 2개(\\)로 수정!
                    parsedHtml = parsedHtml.replace(/MATHBLOCK(\\d+)ENDMATH/g, function(match, index) {
                        return mathBlocks[index];
                    });
                    parsedHtml = parsedHtml.replace(/MATHINLINE(\\d+)ENDMATH/g, function(match, index) {
                        return mathBlocks[index];
                    });

                    // 스크롤 마커 토큰을 실제 마커 요소로 변환.
                    // (이스케이프를 거친 뒤이므로, 이 시점에 넣는 태그만 실제 HTML로 동작함)
                    parsedHtml = parsedHtml.replace(/<p>\\s*\\[\\[TURN_START\\]\\]\\s*<\\/p>/g, '<div class="turn-start"></div>');
                    parsedHtml = parsedHtml.replace(/\\[\\[TURN_START\\]\\]/g, '<div class="turn-start"></div>');

                    // 사용자 질문 영역을 굵고 크게 표시.
                    // 보통은 한 문단 안에 들어오지만, 질문에 빈 줄이 있으면 문단이 쪼개지므로
                    // 안쪽에 남은 </p><p>는 줄바꿈으로 정리해서 태그가 어긋나지 않게 함.
                    function buildQuestionBlock(inner, tag) {
                        const cleaned = inner.replace(/<\\/p>\\s*<p>/g, '<br>');
                        return '<' + tag + ' class="user-question">Q. ' + cleaned + '</' + tag + '>';
                    }
                    parsedHtml = parsedHtml.replace(/<p>\\s*\\[\\[Q\\]\\]([\\s\\S]*?)\\[\\[\\/Q\\]\\]\\s*<\\/p>/g, function(match, inner) {
                        return buildQuestionBlock(inner, 'div');
                    });
                    parsedHtml = parsedHtml.replace(/\\[\\[Q\\]\\]([\\s\\S]*?)\\[\\[\\/Q\\]\\]/g, function(match, inner) {
                        return buildQuestionBlock(inner, 'span');
                    });
                    
                    document.getElementById('content').innerHTML = parsedHtml;
                    renderMathInElement(document.getElementById('content'), {
                        delimiters: [
                            {left: '$$', right: '$$', display: true},
                            {left: '$', right: '$', display: false}
                        ],
                        throwOnError: false
                    });

                    // 새 질문(턴)이 시작되면, 사용자가 위로 올려둔 상태였더라도 다시 따라가기를 켬
                    const markers = document.querySelectorAll('#content .turn-start');
                    if (markers.length !== lastTurnCount) {
                        lastTurnCount = markers.length;
                        autoFollow = true;
                    }

                    // 답변이 스트리밍되는 동안 화면을 계속 아래로 따라가게 함.
                    // (사용자가 위로 스크롤해서 읽는 중이면 autoFollow가 꺼져 있어 방해하지 않음)
                    if (autoFollow) {
                        springScrollTo(maxScroll());
                    }
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sendTextToWebView(webView: webView, text: text)
    }
}
