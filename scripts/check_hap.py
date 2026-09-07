"""核对已构建应用包的 M1 发布边界，不替代签名、真机或完整安全审计。"""

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HAP = ROOT / "entry/build/default/outputs/default/entry-default-unsigned.hap"
TEST_MARKERS = ("MediaFixture", "FixtureGalleryWriter", "fixture_pages", "ohosTest", "entry_test")


def check_hap(archive):
    with ZipFile(archive) as hap:
        names = hap.namelist()
        if len(names) != len(set(names)):
            raise ValueError("HAP 包含重名条目")
        manifest = json.loads(hap.read("module.json"))
        app, module = manifest["app"], manifest["module"]
        if app["bundleName"] != "com.chr.Yi_Da" or module["name"] != "entry":
            raise ValueError("不是当前应用的正式 entry 模块")
        # 26.0.0.105 编译器实际输出的编码值，不能把它误改为普通整数 26。
        # 升级 SDK 时应重新审查版本格式，不要只放宽断言以消除失败。
        if (app["minAPIVersion"] != 260000026 or app["targetAPIVersion"] != 260000026
                or not app["compileSdkVersion"].startswith("26.0.0.")):
            raise ValueError("HAP 未保持 API 26.0.0 编译/兼容基线")
        if [ability["name"] for ability in module.get("abilities", [])] != ["EntryAbility"]:
            raise ValueError("正式 HAP 包含未审查的 Ability")
        if [ability["name"] for ability in module.get("extensionAbilities", [])] != ["EntryBackupAbility"]:
            raise ValueError("正式 HAP 包含未审查的 ExtensionAbility")
        # M1 通过用户主动 Picker 选择读取照片，不需要全量图库权限。
        # 后续接入相机/网络时必须同步审查清单和测试，不能静默扩大权限。
        if module.get("requestPermissions"):
            raise ValueError("正式 HAP 新增权限，需要人工审查")
        backup = json.loads(hap.read("resources/base/profile/backup_config.json"))
        if backup.get("allowToBackupRestore") is not False:
            raise ValueError("自动备份未关闭")
        for name in names:
            if any(marker in name for marker in TEST_MARKERS):
                raise ValueError("正式 HAP 包含测试文件")
            if name.endswith((".json", ".map", ".abc", ".info")):
                content = hap.read(name)
                if any(marker.encode("utf-8") in content for marker in TEST_MARKERS):
                    raise ValueError("正式 HAP 的代码或配置含测试入口")
        if not hap.read("ets/modules.abc"):
            raise ValueError("缺少应用字节码")
        if not hap.read("resources/rawfile/demo/NOTICE.txt"):
            raise ValueError("缺少内置素材署名")
        return app["compileSdkVersion"], len(names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hap", type=Path, default=DEFAULT_HAP)
    args = parser.parse_args()
    sdk, entries = check_hap(args.hap)
    digest = hashlib.sha256(args.hap.read_bytes()).hexdigest()
    print(f"PASS: SDK {sdk}; {entries} entries; no test entry or declared permissions; backup disabled")
    print(f"SHA-256: {digest}")
    print("Scope: built HAP boundary only; signing and physical device remain unverified.")


if __name__ == "__main__":
    main()
