import Foundation

// 四级嵌套模型
struct GroupHierarchy: Identifiable { // 对应 macOS 群组
    let id: String
    let name: String
    var lists: [ListHierarchy]
}

struct ListHierarchy: Identifiable { // 对应 macOS 列表
    let id: String
    let name: String
    var sections: [SectionHierarchy]
}

struct SectionHierarchy: Identifiable { // 对应 macOS 分区
    let id: String
    let name: String
    var tasks: [FeishuTask]
}

class TaskViewModel: ObservableObject {
    @Published var hierarchy: [GroupHierarchy] = []

    func processTasks(tasks: [FeishuTask], sections: [FeishuSection]) {
        let tasksBySection = Dictionary(grouping: tasks) { task in
            task.tasklists?.first?.sectionGuid ?? "default_section"
        }
        let sectionHierarchy = sections.map { section in
            SectionHierarchy(id: section.guid, name: section.name, tasks: tasksBySection[section.guid] ?? [])
        }
        let independentTasks = tasksBySection["default_section"] ?? []
        let allSections = sectionHierarchy + [SectionHierarchy(id: "default_section", name: "未分组", tasks: independentTasks)]
        hierarchy = [GroupHierarchy(id: "default_group", name: "飞书", lists: [ListHierarchy(id: "default_list", name: "任务", sections: allSections)])]
    }

    // 将扁平数据重组为四级结构
    // listToSections: 传入一个字典，key 为清单ID，value 为该清单下的所有分区
    func processTasks(tasks: [FeishuTask], lists: [FeishuTasklist], groups: [FeishuTasklistGroup], listToSections: [String: [FeishuSection]]) {

        // 1. 将任务按 Section ID 归类
        var tasksBySection: [String: [FeishuTask]] = [:]
        for task in tasks {
            if let sectionId = task.tasklists?.first?.sectionGuid {
                tasksBySection[sectionId, default: []].append(task)
            }
        }

        // 2. 将 Section 按 List 归类
        var sectionsByList: [String: [SectionHierarchy]] = [:]
        for (listId, sectionsInList) in listToSections {
            sectionsByList[listId] = sectionsInList.map { section in
                SectionHierarchy(id: section.guid, name: section.name, tasks: tasksBySection[section.guid] ?? [])
            }
        }

        // 3. 将 List 按 Group ID 归类
        var listsByGroup: [String: [ListHierarchy]] = [:]
        for list in lists {
            let groupId = list.groupGuid ?? "default_group"
            let listHierarchy = ListHierarchy(id: list.guid, name: list.name, sections: sectionsByList[list.guid] ?? [])
            listsByGroup[groupId, default: []].append(listHierarchy)
        }

        // 4. 组装最终四级层级
        self.hierarchy = groups.map { group in
            GroupHierarchy(id: group.guid, name: group.name, lists: listsByGroup[group.guid] ?? [])
        }

        // 处理未分组清单
        if let defaultLists = listsByGroup["default_group"], !defaultLists.isEmpty {
            self.hierarchy.append(GroupHierarchy(id: "default_group", name: "未分组", lists: defaultLists))
        }
    }
}
