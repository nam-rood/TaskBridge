import Foundation

// MARK: - 飞书 API 数据模型

struct FeishuTask: Codable {
    let guid: String
    let summary: String
    let completedAt: String?
    let due: Due?
    let tasklists: [TasklistRef]?

    init(guid: String, summary: String, completedAt: String? = nil, due: Due? = nil, tasklists: [TasklistRef]? = nil) {
        self.guid = guid
        self.summary = summary
        self.completedAt = completedAt
        self.due = due
        self.tasklists = tasklists
    }

    enum CodingKeys: String, CodingKey {
        case guid
        case summary
        case completedAt
        case due
        case tasklists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guid = try container.decode(String.self, forKey: .guid)
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        completedAt = Self.decodeFlexibleString(from: container, forKey: .completedAt)
        due = try? container.decodeIfPresent(Due.self, forKey: .due)
        tasklists = try? container.decodeIfPresent([TasklistRef].self, forKey: .tasklists)
    }

    private static func decodeFlexibleString(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    struct Due: Codable {
        let timestamp: String
        let isAllDay: Bool

        init(timestamp: String, isAllDay: Bool) {
            self.timestamp = timestamp
            self.isAllDay = isAllDay
        }

        enum CodingKeys: String, CodingKey {
            case timestamp
            case isAllDay
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decode(String.self, forKey: .timestamp) {
                timestamp = value
            } else if let value = try? container.decode(Int.self, forKey: .timestamp) {
                timestamp = String(value)
            } else if let value = try? container.decode(Int64.self, forKey: .timestamp) {
                timestamp = String(value)
            } else {
                timestamp = ""
            }
            isAllDay = (try? container.decode(Bool.self, forKey: .isAllDay)) ?? false
        }
    }

    struct TasklistRef: Codable {
        let tasklistGuid: String
        let sectionGuid: String?
    }
}

struct FeishuTasklist: Codable {
    let guid: String
    let name: String
    let groupGuid: String?
}

struct FeishuSection: Codable {
    let guid: String
    let name: String
}

// 新增：清单分组模型
struct FeishuTasklistGroup: Codable {
    let guid: String
    let name: String
}

// 新增：清单分组列表响应模型
struct FeishuTasklistGroupsResponse: Codable {
    let code: Int
    let msg: String
    let data: GroupData?

    struct GroupData: Codable {
        let items: [FeishuTasklistGroup]?
    }
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

struct FeishuTaskCreateResponse: Codable {
    let code: Int
    let msg: String
    let data: TaskCreateData?

    struct TaskCreateData: Codable {
        let task: FeishuTask?
        let item: FeishuTask?
        let guid: String?
        let taskGuid: String?
    }
}

struct FeishuUserInfoResponse: Codable {
    let code: Int
    let msg: String
    let data: UserInfoData?

    struct UserInfoData: Codable {
        let openId: String?
        let unionId: String?
        let userId: String?
    }
}

// MARK: - 飞书 API 客户端

class FeishuAPIClient {
    static let shared = FeishuAPIClient()

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

    var currentUserOpenId: String? {
        get {
            return UserDefaults.standard.string(forKey: "feishuCurrentUserOpenId")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feishuCurrentUserOpenId")
        }
    }

    private let baseURL = "https://open.feishu.cn/open-apis"

    private init() {}

    private func shouldRefreshToken(response: URLResponse?, data: Data?) -> Bool {
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            return true
        }

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let code = json["code"] as? Int, code == 99991663 || code == 99991664 {
            return true
        }

        if let message = json["msg"] as? String {
            let normalized = message.lowercased()
            if normalized.contains("token expired") || normalized.contains("authentication token expired") {
                return true
            }
        }

        return false
    }

    func clearAuthorizationState() {
        userAccessToken = nil
        userRefreshToken = nil
        currentUserOpenId = nil
    }

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

            if self.shouldRefreshToken(response: response, data: data) {
                print("⚠️ Token 已过期，尝试自动刷新...")
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.fetchTasks(tasklistGuid: tasklistGuid, pageToken: pageToken, accumulatedTasks: accumulatedTasks, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
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
                        self.fetchTasks(tasklistGuid: tasklistGuid, pageToken: nextToken, accumulatedTasks: allTasks, completion: completion)
                    } else {
                        DispatchQueue.main.async { completion(.success(allTasks)) }
                    }
                } else {
                    let error = NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: apiResponse.msg])
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                let preview = String(rawResponse.prefix(1000))
                print("JSON 解析失败: \(error)\n响应内容: \(preview)")
                let nsError = NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "解析任务响应失败: \(error.localizedDescription); 响应: \(preview)"])
                DispatchQueue.main.async { completion(.failure(nsError)) }
            }
        }
        task.resume()
    }

    /// 获取飞书清单列表
    func fetchTasklists(pageToken: String? = nil, accumulatedTasklists: [FeishuTasklist] = [], completion: @escaping (Result<[FeishuTasklist], Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        var urlString = "\(baseURL)/task/v2/tasklists?page_size=50"
        if let pt = pageToken, !pt.isEmpty {
            urlString += "&page_token=\(pt)"
        }
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器未返回数据"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.fetchTasklists(pageToken: pageToken, accumulatedTasklists: accumulatedTasklists, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuTasklistsResponse.self, from: data)

                if apiResponse.code == 0 {
                    let items = apiResponse.data?.items ?? []
                    let allTasklists = accumulatedTasklists + items
                    if let hasMore = apiResponse.data?.hasMore, hasMore, let nextToken = apiResponse.data?.pageToken {
                        self.fetchTasklists(pageToken: nextToken, accumulatedTasklists: allTasklists, completion: completion)
                    } else {
                        DispatchQueue.main.async { completion(.success(allTasklists)) }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: apiResponse.msg])))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器未返回分组数据"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { res in
                    switch res {
                    case .success:
                        self.fetchSections(tasklistGuid: tasklistGuid, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuSectionsResponse.self, from: data)

                if apiResponse.code == 0 {
                    let items = apiResponse.data?.items ?? []
                    DispatchQueue.main.async { completion(.success(items)) }
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
    /// 获取单个任务详情
    func fetchTaskDetail(guid: String, completion: @escaping (Result<FeishuTask, Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        let urlString = "\(baseURL)/task/v2/tasks/\(guid)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器未返回任务详情"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.fetchTaskDetail(guid: guid, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                // 假设响应结构与列表获取一致，仅 data.item 为单个任务
                let apiResponse = try decoder.decode(FeishuTaskDetailResponse.self, from: data)
                if apiResponse.code == 0, let task = apiResponse.data?.task ?? apiResponse.data?.item {
                    DispatchQueue.main.async { completion(.success(task)) }
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

    func fetchCurrentUserOpenId(completion: @escaping (Result<String, Error>) -> Void) {
        if let currentUserOpenId = currentUserOpenId, !currentUserOpenId.isEmpty {
            completion(.success(currentUserOpenId))
            return
        }

        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        let url = URL(string: "\(baseURL)/authen/v1/user_info")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器未返回用户信息"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.fetchCurrentUserOpenId(completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuUserInfoResponse.self, from: data)

                if apiResponse.code == 0, let openId = apiResponse.data?.openId, !openId.isEmpty {
                    self.currentUserOpenId = openId
                    DispatchQueue.main.async { completion(.success(openId)) }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                    let message = "获取当前用户 open_id 失败: \(apiResponse.msg); 响应: \(String(rawResponse.prefix(500)))"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: message])))
                    }
                }
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                let message = "解析当前用户信息失败: \(error.localizedDescription); 响应: \(String(rawResponse.prefix(500)))"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: message])))
                }
            }
        }.resume()
    }

    func createTask(summary: String, tasklistGuid: String, sectionGuid: String?, dueTimestamp: String?, isAllDay: Bool, completion: @escaping (Result<FeishuTask, Error>) -> Void) {
        fetchCurrentUserOpenId { result in
            switch result {
            case .success(let openId):
                self.createTask(summary: summary, tasklistGuid: tasklistGuid, sectionGuid: sectionGuid, dueTimestamp: dueTimestamp, isAllDay: isAllDay, assigneeOpenId: openId, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func createTask(summary: String, tasklistGuid: String, sectionGuid: String?, dueTimestamp: String?, isAllDay: Bool, assigneeOpenId: String, completion: @escaping (Result<FeishuTask, Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "任务标题为空"])))
            return
        }

        let urlString = "\(baseURL)/task/v2/tasks"
        guard let url = URL(string: urlString) else { return }

        var taskBody: [String: Any] = [
            "summary": trimmedSummary,
            "members": [[
                "type": "user",
                "id": assigneeOpenId,
                "role": "assignee"
            ]]
        ]
        if !tasklistGuid.isEmpty {
            var tasklist: [String: Any] = ["tasklist_guid": tasklistGuid]
            if let sectionGuid = sectionGuid, !sectionGuid.isEmpty {
                tasklist["section_guid"] = sectionGuid
            }
            taskBody["tasklists"] = [tasklist]
        }
        if let dueTimestamp = dueTimestamp {
            taskBody["due"] = [
                "timestamp": dueTimestamp,
                "is_all_day": isAllDay
            ]
        }

        let body = taskBody

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器未返回创建任务响应"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.createTask(summary: summary, tasklistGuid: tasklistGuid, sectionGuid: sectionGuid, dueTimestamp: dueTimestamp, isAllDay: isAllDay, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let apiResponse = try decoder.decode(FeishuTaskCreateResponse.self, from: data)

                if apiResponse.code == 0 {
                    if let task = apiResponse.data?.task ?? apiResponse.data?.item {
                        DispatchQueue.main.async { completion(.success(task)) }
                    } else if let guid = apiResponse.data?.guid ?? apiResponse.data?.taskGuid {
                        let tasklists = tasklistGuid.isEmpty ? nil : [FeishuTask.TasklistRef(tasklistGuid: tasklistGuid, sectionGuid: sectionGuid)]
                        let task = FeishuTask(guid: guid, summary: trimmedSummary, due: dueTimestamp.map { FeishuTask.Due(timestamp: $0, isAllDay: isAllDay) }, tasklists: tasklists)
                        DispatchQueue.main.async { completion(.success(task)) }
                    } else {
                        let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                        let message = "创建飞书任务成功但响应缺少任务 ID: \(String(rawResponse.prefix(500)))"
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: message])))
                        }
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                    let message = "创建飞书任务失败: \(apiResponse.msg); 响应: \(String(rawResponse.prefix(500)))"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "FeishuAPI", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: message])))
                    }
                }
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                let message = "解析创建任务响应失败: \(error.localizedDescription); 响应: \(String(rawResponse.prefix(500)))"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: message])))
                }
            }
        }.resume()
    }

    func updateTask(guid: String, summary: String? = nil, isCompleted: Bool? = nil, dueTimestamp: String? = nil, isAllDay: Bool = false, shouldUpdateDue: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        var taskPayload: [String: Any] = [:]
        var updateFields: [String] = []

        if let summary = summary {
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSummary.isEmpty else {
                completion(.failure(NSError(domain: "FeishuAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "任务标题为空"])))
                return
            }
            taskPayload["summary"] = trimmedSummary
            updateFields.append("summary")
        }

        if let isCompleted = isCompleted {
            taskPayload["completed_at"] = isCompleted ? String(Int64(Date().timeIntervalSince1970 * 1000)) : "0"
            updateFields.append("completed_at")
        }

        if shouldUpdateDue {
            if let dueTimestamp = dueTimestamp, !dueTimestamp.isEmpty {
                taskPayload["due"] = [
                    "timestamp": dueTimestamp,
                    "is_all_day": isAllDay
                ]
            } else {
                taskPayload["due"] = NSNull()
            }
            updateFields.append("due")
        }

        guard !updateFields.isEmpty else {
            completion(.success(()))
            return
        }

        let urlString = "\(baseURL)/task/v2/tasks/\(guid)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "task": taskPayload,
            "update_fields": updateFields
        ])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "解析任务更新响应失败"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.updateTask(guid: guid, summary: summary, isCompleted: isCompleted, dueTimestamp: dueTimestamp, isAllDay: isAllDay, shouldUpdateDue: shouldUpdateDue, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "解析任务更新响应失败"])))
                }
                return
            }

            let code = json["code"] as? Int ?? 0
            if code == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = json["msg"] as? String ?? "未知错误"
                let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "\(msg); 响应: \(String(rawResponse.prefix(500)))"])))
                }
            }
        }.resume()
    }

    /// 更新飞书任务完成状态
    func updateTaskStatus(guid: String, isCompleted: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(guid: guid, isCompleted: isCompleted, completion: completion)
    }

    func deleteTask(guid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = userAccessToken else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "未登录"])))
            return
        }

        let urlString = "\(baseURL)/task/v2/tasks/\(guid)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "FeishuAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的任务地址"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "解析删除任务响应失败"])))
                }
                return
            }

            if self.shouldRefreshToken(response: response, data: data) {
                FeishuOAuthManager.shared.refreshUserAccessToken { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.deleteTask(guid: guid, completion: completion)
                    case .failure(let refreshError):
                        DispatchQueue.main.async { completion(.failure(refreshError)) }
                    }
                }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "解析删除任务响应失败"])))
                }
                return
            }

            let code = json["code"] as? Int ?? 0
            if code == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = json["msg"] as? String ?? "未知错误"
                let rawResponse = String(data: data, encoding: .utf8) ?? "无法读取响应内容"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FeishuAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "\(msg); 响应: \(String(rawResponse.prefix(500)))"])))
                }
            }
        }.resume()
    }

// 辅助模型
struct FeishuTaskDetailResponse: Codable {
    let code: Int
    let msg: String
    let data: TaskDetailData?
    struct TaskDetailData: Codable {
        let item: FeishuTask?
        let task: FeishuTask?
    }
}
}