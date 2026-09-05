"""从唯一 SQL 基线生成 ArkData 逐句迁移资源；--check 仅验证同步。"""

import argparse
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/database/schema.sql"
TARGET = ROOT / "entry/src/main/resources/rawfile/database/v1.json"


def statements():
    pending = ""
    result = []
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("--"):
            continue
        pending += line + "\n"
        if sqlite3.complete_statement(pending):
            statement = pending.strip()
            if statement != "PRAGMA foreign_keys = ON;":
                result.append(statement)
            pending = ""
    assert not pending.strip(), "Incomplete SQL"
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = json.dumps(statements(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        assert TARGET.read_text(encoding="utf-8") == text, "Run scripts/generate_schema.py"
        print("Migration resource matches schema.sql.")
    else:
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        TARGET.write_text(text, encoding="utf-8")
        print("Generated database/v1.json.")
