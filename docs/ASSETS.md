# 演示图片来源

本目录记录艺搭演示版内置图片。图片仅代表预置的示例衣物，不表示用户真实拥有；应用内显示“示例衣橱”。使用者自己的导入照片保存在应用沙箱。

衬衫、外套和运动鞋也出现在录入页的「示例照片」中。选择后会复制成独立的应用沙箱 PNG，逐件确认后才加入衣橱；它们不会被写入系统相册。

图片来自 Unsplash 图片 CDN，使用依据：https://unsplash.com/license 。不使用《搭搭》的界面、代码或图片资产。

| 本地文件 | 图片标识 | 用途 |
| --- | --- | --- |
| demo_tee.jpg | photo-1521572163474-6864f9cf17ab | 白色短袖 |
| demo_jeans.jpg | photo-1542272604-787c3835535d | 牛仔裤 |
| demo_sneakers.jpg | photo-1549298916-b41d501d3772 | 运动鞋 |
| demo_shirt.jpg | photo-1596755094514-f87e34085b2c | 衬衫 |
| demo_jacket.jpg | photo-1551028719-00167b16eac5 | 外套 |
| demo_knit.jpg | photo-1576566588028-4147f3842f27 | 米白印花短袖 |

下载日期：2026-09-13。应用展示使用打包资源，无需运行时联网。对图片中的品牌不作背书。

## 端侧模型

`entry/src/main/resources/rawfile/mobilenetv2.ms` 来自 MindSpore Lite Model Zoo 的
MobileNetV2 ImageNet 模型。模型文件用于端侧推理候选提示，不能直接证明专用服装分类准确率；
应用只映射少量与衣橱大类相符的标签，并要求用户确认。MindSpore Model Zoo 代码与模型生态遵循
Apache License 2.0，模型下载地址为：
https://download.mindspore.cn/model_zoo/official/lite/quick_start/mobilenetv2.ms
