import Foundation

// MARK: - 飞书 API 数据模型

struct FeishuTask: Codable {
    let guid: String
    let summary: String
    let completedAt: String?
    let due: Due?
    // 新增：任务所属的分组 ID
    let tasklists: [TasklistRef]?

    struct Due: Codable {
        let timestamp: String
        let isAllDay: Bool
    }

    struct TasklistRef: Codable {
        let tasklistGuid: String
        let sectionGuid: String?
    }
}

struct FeishuTasklist: Codable {
    let guid: String
    let name: String
}

// 新增：飞书分组模型
struct FeishuSection: Codable {
    let guid: String
    let name: String
}

struct FeishuTaskListResponse: Codable {
    let code: Int
    let msg: String
    let data: TaskData?

    struct TaskData: Codable {
        let items: [FeishuTask]?
        let pageToken: String?
        let hasMore: Bool?
    }
}

struct FeishuTasklistsResponse: Codable {
    let code: Int
    let msg: String
    let data: TasklistData?

    struct TasklistData: Codable {
        let items: [FeishuTasklist]?
        let pageToken: String?
        let hasMore: Bool?
    }
}

// 新增：分组列表响应模型
struct FeishuSectionsResponse: Codable {
    let code: Int
    let msg: String
    let data: SectionData?

    struct SectionData: Codable {
        let items: [FeishuSection]?
        let pageToken: String?
        let hasMore: Bool?
    }
}

// MARK: - 飞书 API 客户端

class FeishuAPIClient {
    static let shared = FeishuAPIClient()

    // TODO: 替换为在飞书开放平台申请的真实 App ID 和 App Secret
    private let appId = "YOUR_APP_ID"
    private let appSecret = "YOUR_APP_SECRET"

    // 用户的 Access Token，使用 UserDefaults 持久化保存，避免每次重启都需要重新授权
    var userAccessToken: String? {
        get {
            return UserDefaults.standard.string(forKey: "feishuUserAccessToken")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feishuUserAccessToken")
        }
    }

    // 用户的 Refresh Token，用于刷新过期的 Access Token
    var userRefreshToken: String? {
        get {
            return UserDefaults.standard.string(forKey: "feishuUserRefreshToken")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feishuUserRefreshToken")
        }
    }

    private let baseURL = "https://open.feishu.cn/open-apis"

    private init() {}

    /// 获取飞书任务列表 (使用 Task v2 API)，自动处理分页拉取所有任务
    /// - Parameter tasklistGuid: 如果传入，则获取该清单下的任务；如果不传，则获取独立任务
    func fetchTasks(tasklistGuid: String? = nil, pageToken: String? = nil, accumulatedTasks: [FeishuTask] = [], completion: @escaping (Result<[FeishuTask], Error>) -> Void) {
        guard let token = userAccessToken else {
            let error = NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "缺少 User Access Token，请先登录授权"])
            completion(.failure(error))
            return
        }

        var urlString = "\(baseURL)/task/v2/tasks?page_size=50"
        if let guid = tasklistGuid {
            urlString += "&tasklist_guid=\(guid)"
        }
        if let pt = pageToken, !pt.isEmpty {
            urlString += "&page_token=\(pt)"
        }

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                let error = NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器未返回数据"])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuTaskListResponse.self, from: data)

                if apiResponse.code == 0 {
                    let items = apiResponse.data?.items ?? []
                    let allTasks = accumulatedTasks + items

                    if let hasMore = apiResponse.data?.hasMore, hasMore, let nextToken = apiResponse.data?.pageToken {
                        // 继续拉取下一页
                        self.fetchTasks(tasklistGuid: tasklistGuid, pageToken: nextToken, accumulatedTasks: allTasks, completion: completion)
                    } else {
                        // 所有页拉取完毕
                        DispatchQueue.main.async { completion(.success(allTasks)) }
                    }
                } else if apiResponse.code == 99991663 || apiResponse.code == 99991664 {
                    print("⚠️ Token 已过期，尝试自动刷新...")
                    FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                        switch refreshResult {
                        case .success(_):
                            self.fetchTasks(tasklistGuid: tasklistGuid, pageToken: pageToken, accumulatedTasks: accumulatedTasks, completion: completion)
                        case .failure(let refreshError):
                            DispatchQueue.main.async { completion(.failure(refreshError)) }
                        }
                    }
                } else {
                    let error = NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: apiResponse.msg])
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } catch {
                print("JSON 解析失败: \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// 获取飞书清单下的所有分组 (Sections)
    func fetchSections(tasklistGuid: String, completion: @escaping (Result<[FeishuSection], Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        // 注意：飞书 Task v2 API 中获取分组的正确路径是 /task/v2/sections，并通过 query 参数指定 tasklist_guid
        let urlString = "\(baseURL)/task/v2/sections?page_size=50&resource_type=tasklist&resource_id=\(tasklistGuid)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else { return }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuSectionsResponse.self, from: data)

                if apiResponse.code == 0 {
                    let items = apiResponse.data?.items ?? []
                    DispatchQueue.main.async { completion(.success(items)) }
                } else if apiResponse.code == 99991663 || apiResponse.code == 99991664 {
                    FeishuOAuthManager.shared.refreshUserAccessToken { res in
                        if case .success(_) = res { self.fetchSections(tasklistGuid: tasklistGuid, completion: completion) }
                    }
                } else {
                    let error = NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: apiResponse.msg])
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
    /// 获取飞书清单(文件夹)列表
    func fetchTasklists(completion: @escaping (Result<[FeishuTasklist], Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        let urlString = "\(baseURL)/task/v2/tasklists?page_size=50"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else { return }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuTasklistsResponse.self, from: data)

                if apiResponse.code == 0 {
                    let items = apiResponse.data?.items ?? []
                    DispatchQueue.main.async { completion(.success(items)) }
                } else if apiResponse.code == 99991663 || apiResponse.code == 99991664 {
                    FeishuOAuthManager.shared.refreshUserAccessToken { res in
                        if case .success(_) = res { self.fetchTasklists(completion: completion) }
                    }
                } else {
                    let error = NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: apiResponse.msg])
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
}