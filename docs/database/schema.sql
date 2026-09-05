-- 艺搭本地数据库 v1 设计参考。
-- 仅用于全新数据库建表和开发验证，不能代替旧库迁移。
-- 正式 ArkData 适配器应逐条 executeSql，并在目标 API 26.0.0 上验证约束与事务。
-- 所有时间为 UTC 毫秒；JSON 字段由领域层按 schemaVersion 校验。
-- 外键需要在连接级启用并用测试确认，不假设所有封装自动开启。
PRAGMA foreign_keys = ON;

CREATE TABLE media_asset (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('garment', 'person', 'result', 'thumbnail')),
    relative_path TEXT NOT NULL UNIQUE,
    sha256 TEXT NOT NULL CHECK (
        length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*'
    ),
    mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
    width INTEGER NOT NULL CHECK (width > 0 AND width <= 8192),
    height INTEGER NOT NULL CHECK (height > 0 AND height <= 8192),
    byte_size INTEGER NOT NULL CHECK (byte_size > 0),
    remote_asset_id TEXT,
    remote_expires_at INTEGER,
    created_at INTEGER NOT NULL,
    CHECK (width * height <= 24000000),
    CHECK (length(relative_path) > 0)
);

-- relative_path 必须在文件适配器规范化并确认位于应用沙箱内。
-- SQL 的非空约束不能防止 ../、符号链接或路径穿越，不能替代文件边界检查。
CREATE INDEX idx_media_sha256 ON media_asset(sha256);

CREATE TABLE garment (
    id TEXT PRIMARY KEY NOT NULL,
    space TEXT NOT NULL CHECK (space IN ('personal', 'demo')),
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
    category TEXT NOT NULL CHECK (
        category IN ('top', 'outerwear', 'bottom', 'dress', 'shoes', 'accessory')
    ),
    color_group TEXT NOT NULL DEFAULT 'unknown',
    season_mask INTEGER NOT NULL DEFAULT 0 CHECK (season_mask BETWEEN 0 AND 15),
    temp_min_c REAL,
    temp_max_c REAL,
    status TEXT NOT NULL DEFAULT 'wearable' CHECK (
        status IN ('wearable', 'laundry', 'stored', 'season_hidden', 'archived')
    ),
    -- 手工无图录入保存 NULL，不伪造图片；后续试穿必须单独检查有可用主图。
    image_asset_id TEXT REFERENCES media_asset(id) ON DELETE RESTRICT,
    thumbnail_asset_id TEXT REFERENCES media_asset(id) ON DELETE RESTRICT,
    cutout_asset_id TEXT REFERENCES media_asset(id) ON DELETE RESTRICT,
    attributes_json TEXT NOT NULL DEFAULT '{}',
    recognition_json TEXT NOT NULL DEFAULT '{}',
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (temp_min_c IS NULL OR temp_max_c IS NULL OR temp_min_c <= temp_max_c),
    CHECK (updated_at >= created_at)
);

CREATE INDEX idx_garment_candidates ON garment(space, status, category, updated_at);
CREATE INDEX idx_garment_name ON garment(space, name);

CREATE TABLE garment_tag (
    garment_id TEXT NOT NULL REFERENCES garment(id) ON DELETE CASCADE,
    tag TEXT NOT NULL CHECK (length(trim(tag)) BETWEEN 1 AND 32),
    PRIMARY KEY (garment_id, tag)
);

CREATE INDEX idx_garment_tag_lookup ON garment_tag(tag, garment_id);

CREATE TABLE outfit (
    id TEXT PRIMARY KEY NOT NULL,
    space TEXT NOT NULL CHECK (space IN ('personal', 'demo')),
    title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 80),
    scene TEXT NOT NULL CHECK (
        scene IN ('campus', 'defense', 'commute', 'interview', 'weekend')
    ),
    temp_min_c REAL,
    temp_max_c REAL,
    season_mask INTEGER NOT NULL CHECK (season_mask BETWEEN 0 AND 15),
    context_json TEXT NOT NULL,
    reasons_json TEXT NOT NULL,
    algorithm_version TEXT NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (temp_min_c IS NULL OR temp_max_c IS NULL OR temp_min_c <= temp_max_c),
    CHECK (updated_at >= created_at)
);

CREATE INDEX idx_outfit_recent ON outfit(space, updated_at);

CREATE TABLE outfit_item (
    outfit_id TEXT NOT NULL REFERENCES outfit(id) ON DELETE CASCADE,
    slot TEXT NOT NULL CHECK (
        slot IN ('top', 'outerwear', 'bottom', 'dress', 'shoes', 'accessory')
    ),
    garment_id TEXT REFERENCES garment(id) ON DELETE SET NULL,
    garment_version INTEGER NOT NULL CHECK (garment_version >= 1),
    is_locked INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1)),
    snapshot_json TEXT NOT NULL,
    PRIMARY KEY (outfit_id, slot),
    UNIQUE (outfit_id, garment_id)
);

-- snapshot_json 保留保存时的展示语义，但永久删除素材时必须由 Repository
-- 清除其中的路径、云图片 ID 等敏感引用。数据库不会自动修改 JSON 内部字段。
CREATE INDEX idx_outfit_item_garment ON outfit_item(garment_id);

CREATE TABLE wear_log (
    id TEXT PRIMARY KEY NOT NULL,
    outfit_id TEXT REFERENCES outfit(id) ON DELETE SET NULL,
    outfit_snapshot_json TEXT NOT NULL,
    local_date TEXT NOT NULL CHECK (
        length(local_date) = 10 AND local_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
    ),
    scene TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
);

-- 日期格式只做形状检查，闰年与真实日期由业务层校验。
-- 同一天允许换装；防止连续点击的重复写入应复用同一个客户端操作 ID。
CREATE INDEX idx_wear_log_date ON wear_log(local_date, created_at);

CREATE TABLE outfit_feedback (
    id TEXT PRIMARY KEY NOT NULL,
    outfit_id TEXT REFERENCES outfit(id) ON DELETE SET NULL,
    garment_id TEXT REFERENCES garment(id) ON DELETE SET NULL,
    feedback_type TEXT NOT NULL CHECK (
        feedback_type IN ('too_cold', 'too_hot', 'dislike', 'unavailable', 'like')
    ),
    context_json TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_feedback_outfit ON outfit_feedback(outfit_id, created_at);

CREATE TABLE person_template (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
    is_demo INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (updated_at >= created_at)
);

CREATE TABLE person_pose (
    template_id TEXT NOT NULL REFERENCES person_template(id) ON DELETE CASCADE,
    pose_key TEXT NOT NULL CHECK (pose_key IN ('front', 'side', 'action')),
    image_asset_id TEXT NOT NULL REFERENCES media_asset(id) ON DELETE RESTRICT,
    quality_json TEXT NOT NULL,
    confirmed_at INTEGER,
    PRIMARY KEY (template_id, pose_key),
    UNIQUE (template_id, image_asset_id)
);

-- SQL 限定每姿势最多一张。模板在草稿阶段可不足三张；
-- 正式提交前由业务事务校验恰好三个不同内容的输入且均已确认。
CREATE TABLE consent_receipt (
    id TEXT PRIMARY KEY NOT NULL,
    purpose TEXT NOT NULL CHECK (purpose IN ('cloud_upload', 'cloud_tryon', 'cloud_retry')),
    notice_version TEXT NOT NULL,
    selected_hashes_json TEXT NOT NULL,
    confirmed_at INTEGER NOT NULL,
    revoked_at INTEGER,
    CHECK (revoked_at IS NULL OR revoked_at >= confirmed_at)
);

CREATE TABLE tryon_job (
    id TEXT PRIMARY KEY NOT NULL,
    client_request_id TEXT NOT NULL UNIQUE,
    remote_job_id TEXT UNIQUE,
    parent_local_job_id TEXT REFERENCES tryon_job(id) ON DELETE SET NULL,
    remote_parent_job_id TEXT,
    outfit_id TEXT REFERENCES outfit(id) ON DELETE SET NULL,
    template_id TEXT REFERENCES person_template(id) ON DELETE SET NULL,
    consent_receipt_id TEXT REFERENCES consent_receipt(id) ON DELETE SET NULL,
    input_snapshot_json TEXT NOT NULL,
    operation_manifest_json TEXT NOT NULL DEFAULT '{}',
    input_fingerprint TEXT CHECK (
        input_fingerprint IS NULL OR
        (length(input_fingerprint) = 64 AND input_fingerprint NOT GLOB '*[^0-9a-f]*')
    ),
    fingerprint_version TEXT,
    recipe_id TEXT,
    submission_state TEXT NOT NULL CHECK (
        submission_state IN (
            'draft', 'validating', 'uploading', 'submitting',
            'submitted', 'local_failed', 'submission_unknown'
        )
    ),
    remote_status TEXT CHECK (
        remote_status IS NULL OR remote_status IN (
            'queued', 'running', 'succeeded', 'partial_success',
            'failed', 'cancelling', 'cancelled'
        )
    ),
    server_revision INTEGER NOT NULL DEFAULT 0 CHECK (server_revision >= 0),
    execution_source TEXT NOT NULL DEFAULT 'live' CHECK (execution_source IN ('live', 'mock')),
    deletion_state TEXT NOT NULL DEFAULT 'none' CHECK (
        deletion_state IN ('none', 'pending', 'completed')
    ),
    last_error_code TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (updated_at >= created_at),
    CHECK (submission_state <> 'submitted' OR remote_job_id IS NOT NULL OR execution_source = 'mock')
);

CREATE INDEX idx_tryon_restore ON tryon_job(deletion_state, submission_state, remote_status);
CREATE INDEX idx_tryon_fingerprint ON tryon_job(input_fingerprint, recipe_id, created_at);

-- operation_manifest_json 保存上传、提交、取消及重试的操作 ID、幂等键、
-- 载荷摘要和响应资源映射；请求前必须落盘。禁止在其中保存访问或刷新令牌。
CREATE TABLE tryon_pose (
    job_id TEXT NOT NULL REFERENCES tryon_job(id) ON DELETE CASCADE,
    pose_key TEXT NOT NULL CHECK (pose_key IN ('front', 'side', 'action')),
    seed INTEGER NOT NULL CHECK (seed BETWEEN 0 AND 2147483647),
    input_asset_id TEXT REFERENCES media_asset(id) ON DELETE SET NULL,
    input_sha256 TEXT NOT NULL CHECK (
        length(input_sha256) = 64 AND input_sha256 NOT GLOB '*[^0-9a-f]*'
    ),
    status TEXT NOT NULL CHECK (
        status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')
    ),
    result_asset_id TEXT REFERENCES media_asset(id) ON DELETE SET NULL,
    remote_result_asset_id TEXT,
    result_sha256 TEXT CHECK (
        result_sha256 IS NULL OR
        (length(result_sha256) = 64 AND result_sha256 NOT GLOB '*[^0-9a-f]*')
    ),
    result_source TEXT CHECK (
        result_source IS NULL OR result_source IN ('generated', 'reused', 'mock')
    ),
    origin_remote_job_id TEXT,
    generated_at INTEGER,
    expires_at INTEGER,
    error_code TEXT,
    PRIMARY KEY (job_id, pose_key)
);

-- 远端成功但本地尚未下载时 result_asset_id 可以为空，不能因此把推理改为失败。
-- 备用匹配还需校验三条结果、输入指纹、配方和本地文件存在，不能仅查父任务成功。
CREATE INDEX idx_tryon_pose_result ON tryon_pose(result_asset_id);

CREATE TABLE deletion_outbox (
    id TEXT PRIMARY KEY NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL CHECK (scope IN ('job', 'assets', 'all_content')),
    payload_json TEXT NOT NULL,
    remote_deletion_id TEXT,
    state TEXT NOT NULL CHECK (state IN ('pending', 'running', 'completed', 'failed')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_retry_at INTEGER,
    last_error_code TEXT,
    created_at INTEGER NOT NULL,
    completed_at INTEGER
);

-- 删除队列只保留必要 ID 与状态，不保存图片、Token 或完整下载 URL。
-- 此表不能随“清空本地历史”直接被清掉，否则会丢失尚未执行的云删除责任。
CREATE INDEX idx_deletion_due ON deletion_outbox(state, next_retry_at);

PRAGMA user_version = 1;
