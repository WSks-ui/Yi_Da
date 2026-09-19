# 网络通信

> 导航入口：[网络管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/network-management) · [HTTP 请求](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-http-request) · [WebSocket](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-websocket) · [Socket](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-socket)

按项目 SDK 核对 Network Kit 或 Basic Services Kit 的当前 API、权限、错误码、任务生命周期和设备限制。

## 通用边界

- 声明并核对所需网络权限。
- 默认使用安全协议；不要把令牌、密码或个人数据放入 URL、日志或错误文本。
- 明确连接、读取、整体操作的超时，以及用户取消和页面退出行为。
- 区分可重试与不可重试错误；对有副作用请求设计幂等或去重。
- 校验状态码、响应类型、长度、编码和业务 schema 后再使用。
- 将平台错误、传输错误、协议错误和业务错误保留为可诊断结果。
- 连接和请求对象需按官方契约释放；监听器要对称注销。

## HTTP

- 每个请求对象有明确所有者，确认完成、失败和取消后的销毁时机。
- 不假设响应一定是字符串或合法 JSON。
- 限制响应大小，并为大文件选择下载能力而非一次性载入内存。
- 处理重定向、认证过期、重复提交、离线、弱网和乱序响应。
- UI 状态更新前确认结果仍属于当前页面和当前请求。

## WebSocket 与 Socket

- 定义连接状态机：连接中、已连接、重连中、关闭和永久失败。
- 注册消息/错误/关闭监听后，保留相同实例用于释放。
- 重连使用退避、上限和取消，避免网络恢复时形成重连风暴。
- 解析消息前做类型、长度和 schema 校验。
- 页面或 Ability 退出时停止心跳、重连和后台回调。
- TCP/UDP 的绑定、地址族和设备能力必须按实际场景与官方 API 验证。

## 上传与下载

- 核对源 URI 访问权和目标路径所有权。
- 校验服务端文件名，避免直接拼接到本地路径。
- 处理进度监听解绑、重复任务、暂停/恢复、部分文件和校验和。
- 对敏感内容明确临时文件清理、缓存和日志策略。

## 网络状态

- “网络可用”不等于目标服务可达。
- 监听网络变化仅作为重试或 UI 提示信号，不替代请求错误处理。
- 注册与注销使用同一连接对象，并覆盖重复进入页面场景。

## 验证

- 成功、超时、断网、弱网、取消、认证过期和服务端错误。
- 非 JSON、超大响应、损坏下载、重复点击和乱序返回。
- 页面退出、Ability 后台/恢复和网络切换。
- 若依赖真实后端或证书环境，明确哪些路径未验证。
