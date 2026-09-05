"""检查开发资料与参考 DDL，不替代 ArkData、ArkTS 或真机验收。"""

import json
import re
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def check_markdown():
    files = sorted((ROOT / "docs").rglob("*.md")) + [ROOT / "README.md"]
    links = 0
    examples = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        assert "\ufffd" not in text, f"Invalid replacement character: {path}"
        assert ":codex-" not in text, f"Unresolved UI citation in source: {path}"
        fence = None
        block = []
        plain = []
        for line in text.splitlines():
            if line.startswith("```"):
                if fence is None:
                    fence = line[3:].strip()
                    block = []
                else:
                    if fence == "json":
                        json.loads("\n".join(block))
                        examples += 1
                    fence = None
                continue
            if fence is None:
                plain.append(line)
            else:
                block.append(line)
        assert fence is None, f"Unclosed code fence: {path}"
        table_width = None
        for line in plain:
            if line.startswith("|"):
                width = len(line.strip().strip("|").split("|"))
                if table_width is None:
                    table_width = width
                assert width == table_width, f"Inconsistent table columns: {path}: {line}"
            else:
                table_width = None
        for target in LINK.findall("\n".join(plain)):
            if target.startswith(("https://", "http://", "#")):
                continue
            target = target.split("#", 1)[0]
            resolved = (path.parent / target).resolve()
            assert resolved.is_relative_to(ROOT), f"Link outside project: {path}: {target}"
            assert resolved.is_file(), f"Broken local link: {path}: {target}"
            links += 1
    return len(files), links, examples


def check_database():
    connection = sqlite3.connect(":memory:")
    connection.executescript((ROOT / "docs/database/schema.sql").read_text(encoding="utf-8"))
    assert connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1
    assert connection.execute("PRAGMA user_version").fetchone()[0] == 1
    tables = connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    assert len(tables) == 13, tables
    checks = 2

    def rejected(sql, values=()):
        nonlocal checks
        connection.execute("SAVEPOINT negative_case")
        try:
            connection.execute(sql, values)
        except sqlite3.IntegrityError:
            checks += 1
        else:
            raise AssertionError(f"Expected database rejection: {sql}")
        finally:
            connection.execute("ROLLBACK TO negative_case")
            connection.execute("RELEASE negative_case")

    media_sql = """INSERT INTO media_asset
        (id,kind,relative_path,sha256,mime_type,width,height,byte_size,created_at)
        VALUES (?,?,?,?,?,?,?,?,?)"""
    connection.execute(media_sql, ("m1", "garment", "media/m1.jpg", "a" * 64,
                                  "image/jpeg", 768, 1024, 1000, 100))
    garment_sql = """INSERT INTO garment
        (id,space,name,category,status,image_asset_id,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?)"""
    connection.execute(garment_sql, ("g1", "personal", "Shirt", "top", "wearable", "m1", 100, 100))
    connection.execute(garment_sql, ("g2", "personal", "Jacket", "outerwear", "stored", "m1", 100, 100))
    # 无图手工录入是正式记录，不以样例照片填充个人衣橱。
    connection.execute(garment_sql, ("g_manual", "personal", "No photo", "top", "wearable", None, 100, 100))
    assert connection.execute("SELECT image_asset_id FROM garment WHERE id='g_manual'").fetchone()[0] is None
    checks += 1
    rejected("UPDATE garment SET thumbnail_asset_id='missing' WHERE id='g_manual'")
    rejected(garment_sql, ("bad_fk", "personal", "Shirt", "top", "wearable", "missing", 100, 100))
    rejected("UPDATE garment SET status='unknown' WHERE id='g1'")
    rejected("UPDATE garment SET category='hat_only' WHERE id='g1'")
    rejected("UPDATE garment SET season_mask=16 WHERE id='g1'")
    rejected("UPDATE garment SET temp_min_c=20,temp_max_c=10 WHERE id='g1'")
    rejected("UPDATE garment SET version=0 WHERE id='g1'")
    rejected("UPDATE garment SET updated_at=0 WHERE id='g1'")
    rejected("UPDATE garment SET name='   ' WHERE id='g1'")
    rejected("DELETE FROM media_asset WHERE id='m1'")
    rejected(media_sql, ("bad_hash", "person", "media/bad.jpg", "z" * 64,
                         "image/jpeg", 768, 1024, 1000, 100))
    rejected(media_sql, ("bad_pixels", "person", "media/large.jpg", "b" * 64,
                         "image/jpeg", 8192, 8192, 1000, 100))

    connection.execute("""INSERT INTO outfit
        (id,space,title,scene,season_mask,context_json,reasons_json,
         algorithm_version,created_at,updated_at)
        VALUES ('o1','personal','Outfit','campus',1,'{}','[]','rules-v1',100,100)""")
    item_sql = """INSERT INTO outfit_item
        (outfit_id,slot,garment_id,garment_version,snapshot_json)
        VALUES ('o1',?,?,1,'{}')"""
    connection.execute(item_sql, ("top", "g1"))
    rejected(item_sql, ("top", "g2"))
    rejected(item_sql, ("outerwear", "g1"))
    connection.execute("DELETE FROM garment WHERE id='g1'")
    assert connection.execute("SELECT garment_id FROM outfit_item").fetchone()[0] is None
    checks += 1

    connection.execute("""INSERT INTO person_template
        (id,name,created_at,updated_at) VALUES ('p1','Person',100,100)""")
    connection.execute(media_sql, ("m2", "person", "media/person.jpg", "b" * 64,
                                  "image/jpeg", 768, 1024, 1000, 100))
    pose_sql = """INSERT INTO person_pose
        (template_id,pose_key,image_asset_id,quality_json) VALUES ('p1',?,'m2','{}')"""
    connection.execute(pose_sql, ("front",))
    rejected(pose_sql, ("front",))
    rejected(pose_sql, ("side",))
    rejected(pose_sql, ("invalid",))

    job_sql = """INSERT INTO tryon_job
        (id,client_request_id,input_snapshot_json,submission_state,created_at,updated_at)
        VALUES (?,?, '{}',?,100,100)"""
    connection.execute(job_sql, ("j1", "request1", "draft"))
    rejected(job_sql, ("j2", "request1", "draft"))
    rejected(job_sql, ("j3", "request3", "submitted"))
    rejected("UPDATE tryon_job SET remote_status='uploading' WHERE id='j1'")
    rejected("UPDATE tryon_job SET input_fingerprint='bad' WHERE id='j1'")
    connection.execute("""INSERT INTO tryon_pose
        (job_id,pose_key,seed,input_sha256,status)
        VALUES ('j1','front',1001,?,'queued')""", ("b" * 64,))
    rejected("UPDATE tryon_pose SET seed=-1 WHERE job_id='j1'")
    connection.execute("DELETE FROM tryon_job WHERE id='j1'")
    assert connection.execute("SELECT count(*) FROM tryon_pose").fetchone()[0] == 0
    checks += 1

    # 验证事务回滚不会留下半批状态；正式应用仍需在 ArkData 上重跑同一场景。
    connection.execute("SAVEPOINT batch_edit")
    connection.execute("UPDATE garment SET status='laundry' WHERE id='g2'")
    connection.execute("ROLLBACK TO batch_edit")
    connection.execute("RELEASE batch_edit")
    assert connection.execute("SELECT status FROM garment WHERE id='g2'").fetchone()[0] == "stored"
    checks += 1
    assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
    assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    checks += 2
    connection.close()
    return len(tables), checks


if __name__ == "__main__":
    file_count, link_count, json_count = check_markdown()
    table_count, check_count = check_database()
    print(f"Markdown: {file_count} files; {link_count} local links; {json_count} JSON examples.")
    print(f"SQLite reference: {table_count} tables; {check_count} checks passed.")
    print("Scope: documentation and desktop SQLite only; no ArkTS build or device validation.")
