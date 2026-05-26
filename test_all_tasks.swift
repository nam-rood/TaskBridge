import Foundation

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

print("=== 拉取所有任务 ===")
fetch(url: "\(baseURL)/task/v2/tasks?page_size=50") { data in
    if let data = data, let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}
