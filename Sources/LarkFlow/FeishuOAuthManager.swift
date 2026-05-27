import Foundation
import AppKit
import Network

class FeishuOAuthManager: NSObject {
    static let shared = FeishuOAuthManager()

    // 从 UserDefaults 读取配置
    var appId: String {
        UserDefaults.standard.string(forKey: "feishuAppId") ?? ""
    }
    var appSecret: String {
        UserDefaults.standard.string(forKey: "feishuAppSecret") ?? ""
    }

    // 使用本地 HTTP 服务器接收回调
    let redirectURI = "http://127.0.0.1:21016/callback"
    private var listener: NWListener?
    private var currentConnection: NWConnection?
    private var loginCompletion: ((Result<String, Error>) -> Void)?

    private override init() {}

    /// 启动 OAuth 登录流程 (包含获取 Code 和换取 Token)
    func startLogin(completion: @escaping (Result<String, Error>) -> Void) {
        guard !appId.isEmpty, !appSecret.isEmpty else {
            let error = NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "请先在偏好设置中填写 App ID 和 App Secret"])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        self.loginCompletion = completion

        // 1. 启动本地 HTTP 服务器监听 21016 端口
        startLocalServer()

        // 2. 拼接飞书 OAuth 2.0 授权 URL
        guard let encodedRedirectURI = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法编码回调地址"])))
            }
            return
        }

        let urlString = "https://open.feishu.cn/open-apis/authen/v1/index?redirect_uri=\(encodedRedirectURI)&app_id=\(appId)&state=larkflow_state"
        guard let authURL = URL(string: urlString) else { return }

        // 3. 使用默认浏览器打开授权页面
        NSWorkspace.shared.open(authURL)
    }

    // MARK: - 本地 HTTP 服务器

    private func startLocalServer() {
        stopLocalServer() // 确保之前的监听已关闭

        do {
            let port = NWEndpoint.Port(integerLiteral: 21016)
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: port)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.start(queue: .main)
            print("🚀 本地回调服务器已启动，监听端口 21016...")
        } catch {
            print("❌ 启动本地服务器失败: \(error)")
            let nsError = NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法启动本地回调服务器，端口 21016 可能被占用"])
            DispatchQueue.main.async { self.loginCompletion?(.failure(nsError)) }
        }
    }

    private func stopLocalServer() {
        listener?.cancel()
        listener = nil
        currentConnection?.cancel()
        currentConnection = nil
    }

    private func handleNewConnection(_ connection: NWConnection) {
        currentConnection = connection
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, let requestString = String(data: data, encoding: .utf8) {
                print("收到 HTTP 请求: \n\(requestString)")

                // 解析 HTTP GET 请求路径
                let lines = requestString.components(separatedBy: .newlines)
                if let firstLine = lines.first, firstLine.hasPrefix("GET") {
                    let parts = firstLine.components(separatedBy: " ")
                    if parts.count > 1 {
                        let path = parts[1]
                        self.handleCallbackPath(path, connection: connection)
                    }
                }
            }

            if error != nil || isComplete {
                connection.cancel()
            }
        }
    }

    private func handleCallbackPath(_ path: String, connection: NWConnection) {
        // 构造一个完整的 URL 以便解析 Query 参数
        guard let url = URL(string: "http://127.0.0.1:21016\(path)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            sendHTTPResponse(to: connection, message: "Invalid Request")
            return
        }

        if let code = queryItems.first(where: { $0.name == "code" })?.value {
            print("✅ 成功获取到授权 Code: \(code)，正在换取 Token...")
            sendHTTPResponse(to: connection, message: "授权成功！您可以关闭此网页并返回 LarkFlow。")

            // 停止服务器
            stopLocalServer()

            // 换取 Token
            exchangeCodeForToken(code: code) { [weak self] result in
                self?.loginCompletion?(result)
            }
        } else {
            sendHTTPResponse(to: connection, message: "未找到授权 Code，请重试。")
        }
    }

    private func sendHTTPResponse(to connection: NWConnection, message: String) {
        let html = """
        <html>
        <head><meta charset="utf-8"><title>LarkFlow 授权</title></head>
        <body style="font-family: sans-serif; text-align: center; padding-top: 50px;">
            <h2>\(message)</h2>
        </body>
        </html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - Token 换取逻辑

    /// 用 Code 换取 User Access Token
    private func exchangeCodeForToken(code: String, completion: @escaping (Result<String, Error>) -> Void) {
        getAppAccessToken { [weak self] result in
            switch result {
            case .success(let appAccessToken):
                self?.getUserAccessToken(code: code, appAccessToken: appAccessToken, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// 获取 App Access Token
    private func getAppAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://open.feishu.cn/open-apis/auth/v3/app_access_token/internal")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "app_id": appId,
            "app_secret": appSecret
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "解析 app_access_token 响应失败"])))
                return
            }

            if let token = json["app_access_token"] as? String {
                completion(.success(token))
            } else {
                // 打印出飞书返回的真实错误信息
                let code = json["code"] as? Int ?? -1
                let msg = json["msg"] as? String ?? "未知错误"
                print("❌ 飞书 API 报错: code=\(code), msg=\(msg)")
                completion(.failure(NSError(domain: "OAuth", code: code, userInfo: [NSLocalizedDescriptionKey: "获取 app_access_token 失败: \(msg)"])))
            }
        }.resume()
    }

    /// 获取 User Access Token
    private func getUserAccessToken(code: String, appAccessToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://open.feishu.cn/open-apis/authen/v1/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(appAccessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let userToken = dataDict["access_token"] as? String,
                  let refreshToken = dataDict["refresh_token"] as? String else {
                completion(.failure(NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "获取 user_access_token 失败"])))
                return
            }

            FeishuAPIClient.shared.userAccessToken = userToken
            FeishuAPIClient.shared.userRefreshToken = refreshToken
            completion(.success(userToken))
        }.resume()
    }

    /// 刷新 User Access Token
    func refreshUserAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let refreshToken = FeishuAPIClient.shared.userRefreshToken else {
            completion(.failure(NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有找到 refresh_token，请重新登录"])))
            return
        }

        getAppAccessToken { result in
            switch result {
            case .success(let appAccessToken):
                let url = URL(string: "https://open.feishu.cn/open-apis/authen/v1/refresh_access_token")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(appAccessToken)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

                let body: [String: String] = [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken
                ]
                request.httpBody = try? JSONEncoder().encode(body)

                URLSession.shared.dataTask(with: request) { data, _, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let dataDict = json["data"] as? [String: Any],
                          let newUserToken = dataDict["access_token"] as? String,
                          let newRefreshToken = dataDict["refresh_token"] as? String else {
                        completion(.failure(NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "刷新 token 失败"])))
                        return
                    }

                    FeishuAPIClient.shared.userAccessToken = newUserToken
                    FeishuAPIClient.shared.userRefreshToken = newRefreshToken
                    print("🔄 Token 刷新成功！")
                    completion(.success(newUserToken))
                }.resume()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}