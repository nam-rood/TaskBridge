# TaskBridge

TaskBridge 是一个 macOS 菜单栏工具，用来在飞书任务和 Apple 提醒事项之间进行双向同步。

如果你平时用飞书协作，但又习惯在 macOS / iPhone / Apple Watch 上通过「提醒事项」查看和处理待办，TaskBridge 可以把两边连接起来：飞书任务会同步到本地提醒事项，本地提醒事项中的变更也会回写到飞书。

> 项目仍处于早期开发阶段，建议先使用测试飞书账号或少量任务验证同步效果。

## 功能特性

- 飞书 OAuth 登录授权
- 飞书任务同步到 Apple 提醒事项
- Apple 提醒事项变更同步回飞书任务
- 支持任务标题、完成状态、截止时间同步
- 支持飞书任务清单和分组映射到 Apple 提醒事项列表
- 自动同步：应用启动后每 120 秒同步一次
- 本地提醒事项变更后自动触发同步
- 飞书 Token 过期后自动刷新
- 菜单栏运行，不占用 Dock
- 本地 SQLite 保存同步映射关系，避免重复创建任务

## 同步规则

### 飞书 → Apple 提醒事项

TaskBridge 会读取飞书任务、清单和分组，并在 Apple 提醒事项中创建对应列表：

- 飞书清单：`飞书 - 清单名`
- 飞书清单分组：`飞书 - 清单名 - 分组名`
- 未归属清单的任务：`飞书 - 我负责的`

同步内容包括：

- 任务标题
- 完成状态
- 截止时间
- 所属清单 / 分组
- 飞书侧删除的任务会同步删除本地对应提醒事项

### Apple 提醒事项 → 飞书

在 TaskBridge 管理的提醒事项列表中，你可以：

- 修改标题
- 修改完成状态
- 修改截止时间
- 新建提醒事项
- 删除提醒事项

这些变更会同步回飞书任务。

## 系统要求

- macOS 13.0 或更高版本
- Xcode 或 Swift 工具链
- 一个飞书开放平台自建应用
- Apple 提醒事项权限

## 安装与运行

### 1. 克隆项目

```bash
git clone <your-repo-url>
cd TaskBridge
```

### 2. 编译运行

开发模式：

```bash
swift run TaskBridge
```

打包为 `.app`：

```bash
./build_app.sh
open TaskBridge.app
```

如果脚本没有执行权限，可以先运行：

```bash
chmod +x build_app.sh
```

## 飞书应用配置

TaskBridge 需要使用你自己的飞书开放平台应用完成 OAuth 授权。

### 1. 创建飞书自建应用

在飞书开放平台创建一个企业自建应用，并获取：

- App ID
- App Secret

### 2. 配置重定向 URL

在飞书应用后台的 OAuth / 安全相关配置中，将下面的地址加入重定向 URL 白名单：

```text
http://127.0.0.1:21016/callback
```

TaskBridge 会在本机临时启动一个 HTTP 回调服务，用于接收飞书 OAuth 授权结果。

### 3. 开通权限

请根据飞书后台提示，为应用开通任务相关读写权限，以及获取当前用户信息所需权限。

TaskBridge 当前会使用以下能力：

- 读取任务列表
- 读取任务清单
- 读取清单分组
- 创建任务
- 更新任务
- 删除任务
- 获取当前授权用户信息

不同飞书后台版本展示的权限名称可能不同，如果授权后提示接口无权限，请按错误提示补充对应权限并重新发布 / 启用应用。

## 使用方法

1. 启动 TaskBridge。
2. 在菜单栏点击 TaskBridge 图标。
3. 点击「偏好设置...」，填写飞书 App ID 和 App Secret。
4. 点击「授权访问」，授予 Apple 提醒事项权限。
5. 点击「飞书授权登录」，在浏览器中完成飞书授权。
6. 回到 TaskBridge，点击「立即同步」开始同步。

授权完成后，TaskBridge 会在后台自动同步。

## 本地数据保存位置

TaskBridge 会在本机保存同步映射和授权信息：

- 同步数据库：`~/Library/Application Support/com.namrood.TaskBridge/taskbridge.sqlite`
- 飞书授权 Token：macOS `UserDefaults`
- 飞书 App ID / App Secret：macOS `UserDefaults`

这些数据只保存在本机，不会上传到除飞书 API 以外的其他服务。

## 隐私与安全说明

- TaskBridge 需要 Apple 提醒事项完全访问权限，用于创建、更新和删除提醒事项。
- TaskBridge 使用你的飞书 OAuth 授权访问任务数据。
- App ID、App Secret 和 Token 当前保存在本机 `UserDefaults` 中。
- 建议不要使用他人提供的未知构建版本，请尽量自行从源码构建。
- 如果你不再使用 TaskBridge，可以在飞书后台取消应用授权，并删除本地数据库。

## 当前限制

- 目前主要同步任务标题、完成状态、截止时间和所属清单 / 分组。
- 暂不支持同步飞书任务描述、评论、附件、子任务等高级字段。
- 冲突处理以最近检测到的变更和本地快照为基础，不适合作为强一致任务系统使用。
- 应用暂未提供正式签名和公证流程。
- OAuth 回调固定使用本机 `21016` 端口，如果端口被占用，授权会失败。

## 开发

项目使用 Swift Package Manager 管理：

```bash
swift build
```

主要依赖：

- SwiftUI：菜单栏界面
- EventKit：访问 Apple 提醒事项
- Network：本地 OAuth 回调服务
- GRDB：本地 SQLite 数据库封装

项目结构：

```text
Sources/TaskBridge/
├── TaskBridge.swift             # 应用入口和菜单栏界面
├── SettingsView.swift         # 偏好设置窗口
├── FeishuOAuthManager.swift   # 飞书 OAuth 登录和 Token 刷新
├── FeishuAPIClient.swift      # 飞书任务 API 客户端
├── EventKitManager.swift      # Apple 提醒事项访问封装
├── SyncEngine.swift           # 飞书到 Apple 的同步逻辑
├── AppleToFeishuSync.swift    # Apple 到飞书的同步逻辑
├── DatabaseManager.swift      # 本地同步映射数据库
└── TaskViewModel.swift        # 任务展示 / 处理模型
```

## 贡献

欢迎提交 Issue 和 Pull Request。

在提交前，建议先运行：

```bash
swift build
```

如果你要调整同步逻辑，请尽量说明：

- 变更影响的同步方向
- 涉及的飞书字段和 Apple 提醒事项字段
- 是否会影响已有同步映射

## License

本项目基于 MIT License 开源。