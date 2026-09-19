# AI 试穿离线演示

本阶段交付固定配套样片的离线体验。无需 API Key，不上传人像，不运行生成模型，不扣试穿额度。

## 演示路径

首页「AI试穿」或搭配详情「试穿样片」进入试穿间；选择牛仔半裙、深蓝上衣或红色连衣裙，查看原图、试穿后或并排对比；保存试穿记录，重启后仍可打开；结果可保存相册或通过系统分享面板分享；记录支持确认删除。

保存结果保持 DEMO / FASHN VTON 1.5 标记。任意衣橱单品不会被映射为这三组固定结果。每组场景只有一条收藏记录，重复保存幂等。旧版「未接入」记录保留，可删除，不补造结果。

## 代码边界

- `service/TryOnDemo.ets`：场景与记录的业务契约，合法场景校验、去重和容量限制。
- `service/TryOnDemoMedia.ets`：稳定场景 ID 到打包资源的映射、离线图片导出与资源释放。
- `pages/TryOnPage.ets`：场景选择、对比、历史查看、系统保存与分享。
- `pages/Index.ets`：继续使用统一 SnapshotCommit，候选快照落盘后才发布记录。失败不改内存；重新提交基于最新快照。
- `TryOnTask.demoSceneId`：可选字段，向后兼容。样片记录不写入用户衣物 ID，不持久化构建期资源数字 ID，`resultUris` 仍为空。

决赛真实接入时增加人像/衣物输入与真实任务状态，在服务层增加生成接口；真实结果使用 `resultUris`，不改变历史 `demoSceneId` 的含义。联网、费用与用户授权只在真实生成入口处理。

## 素材来源

- 作者：FASHN AI（Dan Bochman、Aya Bochman）。
- 项目：https://github.com/fashn-AI/fashn-vton-1.5
- 项目展示页：https://fashn.ai/research/vton-1-5
- 原图为该项目 README 引用的官方展示拼图：https://static.fashn.ai/repositories/fashn-vton-v15/results/hero_collage.webp
- 获取日期：2026-09-18。原图 3410 × 2482。
- SHA256：`18a042c7ed7984bea8d36beed18d7397306260df297ab549c130ec7f263ca088`。
- 仓库声明 Apache-2.0；原许可证随包保存在 `entry/src/main/resources/rawfile/tryon_fashn_license.txt`。展示照片的独立肖像授权范围未在仓库单独列明，正式对外发行前替换为团队取得授权的成套素材。
- 本项目仅裁剪了第一行左组、第二行左右两组，缩放到 560 × 832，增加来源和用途标记；没有重新运行 FASHN 模型，没有把输出归为本项目模型能力。
- 修改脚本：`scripts/prepare-tryon-assets.py`。依赖 Pillow，输入拼图 SHA256 不一致时直接拒绝。保留原图于 `artifacts/tryon-demo/source-collage.webp`。

复现素材：

```text
python scripts/prepare-tryon-assets.py artifacts/tryon-demo/source-collage.webp
```

## 验证

- 构建：API 26 ArkTS 编译、HAP 打包通过；最终包覆盖安装成功。沿用既有签名配置，当前为未签名模拟器包。既有文件 API 与动画弃用警告仍存在。
- 业务回归：81/81，通过实际生产服务及 `Index` 方法验证非法场景、容量、幂等、延迟/失败保存、失败删除、会员额度不变、历史时间格式、入口场景选择。
- 设备：Pura 90 Pro 模拟器，HarmonyOS 7 / API 26，1256 × 2760。仅使用官方 `hdc` / `uitest`。
- 已实测：三场景切换、原图/试穿后/并排对比、保存后立即刷新、冷启动后历史恢复、页内历史回看并滚到顶部、Profile 点记录打开对应场景、删除取消与确认。
- 已实测：相册系统授权弹窗，允许后成功复制图片；系统分享预览正确显示红裙结果和样片标题。未向外部接收人发送图片。
- 证据：`artifacts/tryon-demo/`，包含 `tryon-final.png`、`compare.png`、`navy.png`、`original.png`、`reopened.png`、`share.png` 和对应控件树。
- 数据保护：`saved-state.json` 相比 `before.json` 只多一条试穿记录，额度仍为 0。测试记录通过界面删除后，`after.json` 与 `before.json` 全字段深比较一致。相册保留一张已标记的红裙演示 PNG。
- 未验证：其他尺寸、深色模式、大字号、真机分享接收端。真实生成接口本阶段未接入，不属于已完成功能。
