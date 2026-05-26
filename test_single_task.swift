import Foundation

let token = "u-cpYhID23BdHomKdexOYjAqh46AuQh0Krh8GymBQ028CQ"
let baseURL = "https://open.feishu.cn/open-apis"
let taskGuid = "1d47af89-3d4c-48bd-97e4-1b5034637a39"

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

print("=== 拉取单个任务详情 ===")
fetch(url: "\(baseURL)/task/v2/tasks/\(taskGuid)") { data in
    if let data = data, let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}
