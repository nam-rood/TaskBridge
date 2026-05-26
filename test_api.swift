import Foundation

// 飞书 API 数据模型
struct FeishuTask: Codable {
    let guid: String
    let summary: String
    let completedAt: String?
    let tasklists: [TasklistRef]?

    struct TasklistRef: Codable {
        let tasklistGuid: String
        let sectionGuid: String?
    }
}

struct FeishuTasklist: Codable {
    let guid: String
    let name: String
}

struct FeishuSection: Codable {
    let guid: String
    let name: String
}

struct FeishuTaskListResponse: Codable {
    let code: Int
    let msg: String
    let data: TaskData?
    struct TaskData: Codable { let items: [FeishuTask]? }
}

struct FeishuTasklistsResponse: Codable {
    let code: Int
    let msg: String
    let data: TasklistData?
    struct TasklistData: Codable { let items: [FeishuTasklist]? }
}

struct FeishuSectionsResponse: Codable {
    let code: Int
    let msg: String
    let data: SectionData?
    struct SectionData: Codable { let items: [FeishuSection]? }
}

let token = "u-cpYhID23BdHomKdexOYjAqh46AuQh0Krh8GymBQ028CQ"
let baseURL = "https://open.feishu.cn/open-apis"

func fetch(url: String, completion: @escaping (Data?) -> Void) {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = "GET"
    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, _ in
        completion(data)
        sem.signal()
    }.resume()
    sem.wait()
}

print("=== 开始拉取飞书数据 ===")

// 1. 拉取清单
fetch(url: "\(baseURL)/task/v2/tasklists?page_size=50") { data in
    guard let data = data else { return }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    if let res = try? decoder.decode(FeishuTasklistsResponse.self, from: data), let lists = res.data?.items {
        print("📁 找到 \(lists.count) 个清单:")

        for list in lists {
            print("\n- 清单: [\(list.name)] (ID: \(list.guid))")

            // 2. 拉取分组
            fetch(url: "\(baseURL)/task/v2/sections?page_size=50&resource_type=tasklist&resource_id=\(list.guid)") { secData in
                guard let secData = secData else { return }
                if let secRes = try? decoder.decode(FeishuSectionsResponse.self, from: secData), let sections = secRes.data?.items {
                    if sections.isEmpty {
                        print("  (无分组)")
                    } else {
                        for sec in sections {
                            print("  └─ 分组: [\(sec.name)] (ID: \(sec.guid))")
                        }
                    }
                }
            }

            // 3. 拉取该清单下的任务
            fetch(url: "\(baseURL)/task/v2/tasks?page_size=50&tasklist_guid=\(list.guid)") { taskData in
                guard let taskData = taskData else { return }
                if let taskRes = try? decoder.decode(FeishuTaskListResponse.self, from: taskData), let tasks = taskRes.data?.items {
                    print("  📝 包含 \(tasks.count) 个任务:")
                    for task in tasks {
                        let status = (task.completedAt != nil && task.completedAt != "0") ? "✅" : "⏳"
                        print("    \(status) \(task.summary)")
                    }
                }
            }
        }
    } else {
        print("❌ 解析清单失败或 Token 已过期")
    }
}

// 4. 拉取独立任务
print("\n- 独立任务 (不属于任何清单):")
fetch(url: "\(baseURL)/task/v2/tasks?page_size=50") { data in
    guard let data = data else { return }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    if let res = try? decoder.decode(FeishuTaskListResponse.self, from: data), let tasks = res.data?.items {
        if tasks.isEmpty {
            print("  (无)")
        } else {
            for task in tasks {
                let status = (task.completedAt != nil && task.completedAt != "0") ? "✅" : "⏳"
                print("  \(status) \(task.summary)")
            }
        }
    }
}

print("\n=== 数据拉取完毕 ===")