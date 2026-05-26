import Foundation

let token = "u-cpYhID23BdHomKdexOYjAqh46AuQh0Krh8GymBQ028CQ"
let baseURL = "https://open.feishu.cn/open-apis"
let listGuid = "d3b0229d-b0dd-480a-a075-7f0a7238f6b6" // 任务清单 1

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

print("=== 拉取清单分组 ===")
fetch(url: "\(baseURL)/task/v2/sections?page_size=50&resource_type=tasklist&resource_id=\(listGuid)") { data in
    if let data = data, let str = String(data: data, encoding: .utf8) {
        print(str)

        // 解析出第一个 section 的 guid
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let d = dict["data"] as? [String: Any],
           let items = d["items"] as? [[String: Any]],
           let firstSection = items.first,
           let sectionGuid = firstSection["guid"] as? String {

            print("\n=== 拉取分组下的任务 ===")
            // 尝试通过 section_guid 过滤
            fetch(url: "\(baseURL)/task/v2/tasks?page_size=50&tasklist_guid=\(listGuid)&section_guid=\(sectionGuid)") { data2 in
                if let data2 = data2, let str2 = String(data: data2, encoding: .utf8) {
                    print(str2)
                }
            }
        }
    }
}
