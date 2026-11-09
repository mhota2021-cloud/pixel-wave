import ScreenSaver
import WebKit

//スクリーンセーバー本体のビュー（WKWebViewで描画エンジンを表示する）
//macOSの14以降はスクリーンセーバー終了時にstopAnimationが呼ばれないため、
//分散通知com.apple.screensaver.willstopを受けてWKWebViewを片付ける
@objc(PixelWaveSaverView)
final class PixelWaveSaverView: ScreenSaverView {
    //Webページの表示先
    private var webView: WKWebView?
    //終了通知を受けたかどうか（受けた実例は二度と描画を始めない）
    private var stopped = false

    //初期化（引数frameは表示領域、引数isPreviewは設定画面のプレビューかどうか）
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }

    //ストーリーボード等からの初期化（引数coderは復号器）
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    //共通の初期化（フレーム間隔の設定と終了通知の購読）
    private func setup() {
        animationTimeInterval = 30.0
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(saverWillStop(_:)),
            name: Notification.Name("com.apple.screensaver.willstop"),
            object: nil
        )
    }

    //破棄時の処理（通知の購読をやめる）
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    //表示を始める（WKWebViewを作ってセーバー用ページを読み込む）
    override func startAnimation() {
        super.startAnimation()
        if stopped || webView != nil { return }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(), forURLScheme: "pixelwave")
        let web = WKWebView(frame: bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            web.underPageBackgroundColor = .black
        }
        addSubview(web)
        webView = web
        if let url = URL(string: "pixelwave://saver/saver.html") {
            web.load(URLRequest(url: url))
        }
    }

    //表示を止める（設定画面のプレビュー用、WKWebViewを片付ける）
    override func stopAnimation() {
        teardown()
        super.stopAnimation()
    }

    //1フレーム分の処理（描画はWeb側のrequestAnimationFrameが担うので何もしない）
    override func animateOneFrame() {
    }

    //設定シートは出さない（設定はアプリ側だけにある）
    override var hasConfigureSheet: Bool {
        return false
    }

    //設定シートは無い
    override var configureSheet: NSWindow? {
        return nil
    }

    //スクリーンセーバー終了の通知を受けたときの処理（引数notificationは通知、この実例を無力化して片付ける）
    @objc private func saverWillStop(_ notification: Notification) {
        stopped = true
        teardown()
    }

    //WKWebViewを片付ける（読み込みを止め、階層から外し、参照を手放す）
    private func teardown() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }
}

//pixelwaveスキームへの要求に応える係（バンドルの中のWeb一式と、アプリが書き出した絵を返す）
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    //要求への応答（引数webViewはWebビュー、引数urlSchemeTaskは要求）
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "PixelWaveSaver", code: 1))
            return
        }
        let path = url.path
        if path == "/paintings.js" {
            respond(urlSchemeTask, url: url, data: Data(paintingsScript().utf8), mime: "text/javascript")
            return
        }
        if path.hasPrefix("/images/") {
            let name = (path as NSString).lastPathComponent
            if let data = imageData(named: name) {
                respond(urlSchemeTask, url: url, data: data, mime: "image/jpeg")
            } else {
                urlSchemeTask.didFailWithError(NSError(domain: "PixelWaveSaver", code: 2))
            }
            return
        }
        let name = (path as NSString).lastPathComponent
        if let file = Bundle(for: PixelWaveSaverView.self).url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: "web"
        ), let data = try? Data(contentsOf: file) {
            respond(urlSchemeTask, url: url, data: data, mime: mimeType(for: name))
        } else {
            urlSchemeTask.didFailWithError(NSError(domain: "PixelWaveSaver", code: 3))
        }
    }

    //要求の取り消し（引数webViewはWebビュー、引数urlSchemeTaskは要求、途中でも破棄できるので何もしない）
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    //応答を返す（引数taskは要求、引数urlは要求のURL、引数dataは中身、引数mimeは種類）
    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = URLResponse(
            url: url,
            mimeType: mime,
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    //ファイル名から種類を決める（引数nameはファイル名）
    private func mimeType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html": return "text/html"
        case "js": return "text/javascript"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }

    //絵のデータを探す（引数nameはファイル名、アプリが書き出した場所を先に見て、無ければバンドルの中を見る）
    private func imageData(named name: String) -> Data? {
        let shared = URL(fileURLWithPath: realHomeDirectory())
            .appendingPathComponent("Library/Application Support/PixelWave/images")
            .appendingPathComponent(name)
        if let data = try? Data(contentsOf: shared) {
            return data
        }
        if let file = Bundle(for: PixelWaveSaverView.self).url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: "web/images"
        ) {
            return try? Data(contentsOf: file)
        }
        return nil
    }

    //使う絵の一覧をJavaScriptとして組み立てる（アプリが書き出した設定を先に読み、無ければバンドルの初期設定を使う）
    private func paintingsScript() -> String {
        let shared = URL(fileURLWithPath: realHomeDirectory())
            .appendingPathComponent("Library/Application Support/PixelWave/saver-settings.json")
        var settingsObject: [String: Any]? = nil
        if let data = try? Data(contentsOf: shared) {
            settingsObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        if settingsObject == nil,
           let file = Bundle(for: PixelWaveSaverView.self).url(
               forResource: "default-settings",
               withExtension: "json",
               subdirectory: "web"
           ),
           let data = try? Data(contentsOf: file) {
            settingsObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        var list: [[String: String]] = []
        if let paintings = settingsObject?["paintings"] as? [[String: Any]] {
            for item in paintings {
                if let src = item["src"] as? String {
                    list.append([
                        "src": "pixelwave://saver/" + src,
                        "crop": (item["crop"] as? String) ?? "center",
                    ])
                }
            }
        }
        if let json = try? JSONSerialization.data(withJSONObject: list),
           let text = String(data: json, encoding: .utf8) {
            return "window.PIXELWAVE_PAINTINGS = " + text + ";"
        }
        return "window.PIXELWAVE_PAINTINGS = [];"
    }

    //本当のホームフォルダ（サンドボックスの中ではNSHomeDirectoryがコンテナを指すため、パスワードデータベースから取る）
    private func realHomeDirectory() -> String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }
}
