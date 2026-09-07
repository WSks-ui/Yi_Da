# 艺搭 Yi_Da

面向 HarmonyOS 7 的真实衣橱与智能穿搭参赛项目。

产品主线：使用已有衣物生成可解释、可替换的搭配，再以同一人物的三张姿势照片生成静态试穿预览。

## 开发资料

| 文件 | 用途 |
| --- | --- |
| [完整开发文档](docs/艺搭开发文档.md) | 开发范围、页面、架构、业务规则、数据、AI、鸿蒙能力、实施路线 |
| [服务端接口契约](docs/接口契约.md) | 鉴权、上传、任务、重试、取消、删除、错误码与示例 |
| [数据库设计参考](docs/database/schema.sql) | 本地关系数据库 v1 DDL，不会自动修改应用数据库 |
| [开发任务与验收清单](docs/开发任务与验收清单.md) | 分阶段任务、测试矩阵、发布与现场演示检查 |
| [技术来源与待验证项](docs/技术来源与待验证项.md) | 官方资料、版本证据、模型约束、尚未确定的事项 |

## 当前状态

截至 2026-09-07，保留原 `entry` Stage 工程，本地衣橱首条链路及相册多图导入已实现，未降级 SDK。证据见 [首轮 M0/M1](docs/verification/M0-M1-2026-09-05.md) 与 [本轮 M1 验证](docs/verification/M1-2026-09-07.md)。

- `targetSdkVersion`、`compatibleSdkVersion` 均为 `26.0.0`。
- 当前声明设备类型为 `phone`，不代表已经支持平板。
- 本轮确认实际运行的 IDE 为 `26.0.0.821`，内置 SDK `26.0.0.105 Release`，不再以旧安装推断当前环境。
- 已实现四入口导航、ArkData v1、手工无图录入、单张 Picker、沙箱照片/缩略图、详情编辑、筛选、五种状态、批量编辑、归档恢复与删除。
- 相册队列单次最多 20 张，串行处理，逐件人工确认、失败重试/跳过、暂停/继续、独立保存；同一规范化照片需明确确认重复。未保存队列仅在内存中，杀进程不恢复草稿。
- 批量季节支持任意组合；“不修改季节”与“季节未知”分别处理。保存/取消竞态不会清理已提交照片，清理失败保留重试入口。
- 样例通过用户主动选择导入独立 `demo` 空间；内置照片署名与许可见 `entry/src/main/resources/rawfile/demo/NOTICE.txt`。
- 已通过目标 SDK 未签名 Debug 构建、桌面逻辑测试、API 26 模拟器 ArkData/ImageKit 测试；真实 Picker 选择、数据库保存、删除图库原图后强制停止重读及批量季节编辑均已进行模拟器页面检查。
- `signingConfigs` 仍为空。模拟器允许安装未签名 HAP，不代表真机签名通过；本轮没有真机结果。
- 自动备份已关闭；未接入账号、网络上传、人像、推荐或 AI 试穿。相机、识别/分割、导入草稿跨进程恢复及物理真机回归仍待推进。

## 开始开发

在项目根目录执行：

```powershell
.\scripts\build.ps1 -Task sync
.\scripts\build.ps1
node --test tests\wardrobe.test.cjs
python -m unittest discover -s tests -p test_hap_check.py -v
.\scripts\test-device.ps1
python scripts\check_hap.py
python scripts\generate_schema.py --check
python docs\verification\check_docs.py
```

脚本默认使用本轮验证的 `D:\DevEco Studio 2\DevEco Studio`；其他安装路径通过 `YIDA_DEVECO_HOME` 或 `-DevEcoHome` 指定。设备测试默认针对 `127.0.0.1:5555` 模拟器，失败用例会让脚本报错，不仅检查 `aa test` 的进程退出码。日志与截图保存在被忽略的 `.hvigor`，不自动提交、推送或复制签名。

`check_hap.py` 检查实际构建产物的 API 基线、测试入口隔离、权限声明及备份配置，不代替完整安全审计或签名验证。测试模块提供独立图库夹具，只通过点击系统 SaveButton 写入明确命名的授权示例，不能作为正式功能分发。
