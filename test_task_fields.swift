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

print("=== 拉取清单下的任务 ===")
fetch(url: "\(baseURL)/task/v2/tasks?page_size=10&tasklist_guid=\(listGuid)") { data in
    if let data = data, let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}
