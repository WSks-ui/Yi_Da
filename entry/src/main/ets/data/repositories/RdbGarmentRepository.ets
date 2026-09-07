import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { AppError } from '../../common/errors/AppError';
import { BatchChange, Garment, GarmentDraft, MediaAsset, PreparedPhoto, VersionedId, WardrobeFilter } from '../../domain/models/Garment';
import { GarmentRepository } from '../../domain/repositories/GarmentRepository';
import { validateBatch, validateDraft } from '../../domain/usecases/GarmentRules';
import { AppDatabase } from '../database/AppDatabase';

const SELECT_GARMENT = `SELECT g.*, m.relative_path AS image_path, t.relative_path AS thumbnail_path
  FROM garment g LEFT JOIN media_asset m ON g.image_asset_id=m.id
  LEFT JOIN media_asset t ON g.thumbnail_asset_id=t.id`;

function text(row: relationalStore.ResultSet, column: string): string {
  const index = row.getColumnIndex(column);
  return row.isColumnNull(index) ? '' : row.getString(index);
}

function mapGarment(row: relationalStore.ResultSet): Garment {
  const value = new Garment();
  value.id = text(row, 'id');
  value.space = text(row, 'space');
  value.name = text(row, 'name');
  value.category = text(row, 'category');
  value.colorGroup = text(row, 'color_group');
  value.status = text(row, 'status');
  value.seasonMask = row.getLong(row.getColumnIndex('season_mask'));
  value.version = row.getLong(row.getColumnIndex('version'));
  value.createdAt = row.getLong(row.getColumnIndex('created_at'));
  value.updatedAt = row.getLong(row.getColumnIndex('updated_at'));
  value.imageAssetId = text(row, 'image_asset_id');
  value.thumbnailAssetId = text(row, 'thumbnail_asset_id');
  value.imagePath = text(row, 'image_path');
  value.thumbnailPath = text(row, 'thumbnail_path');
  return value;
}

function mediaValues(value: MediaAsset): relationalStore.ValuesBucket {
  return {
    id: value.id, kind: value.kind, relative_path: value.relativePath, sha256: value.sha256,
    mime_type: value.mimeType, width: value.width, height: value.height,
    byte_size: value.byteSize, created_at: value.createdAt
  };
}

export class RdbGarmentRepository implements GarmentRepository {
  private database: AppDatabase;

  constructor(database: AppDatabase) { this.database = database; }

  async list(filter: WardrobeFilter): Promise<Garment[]> {
    return this.database.run(async (store: relationalStore.RdbStore): Promise<Garment[]> => {
      let sql = `${SELECT_GARMENT} WHERE g.space=?`;
      const args: relationalStore.ValueType[] = [filter.space];
      if (filter.category) { sql += ' AND g.category=?'; args.push(filter.category); }
      if (filter.status) { sql += ' AND g.status=?'; args.push(filter.status); }
      else { sql += " AND g.status<>'archived'"; }
      if (filter.seasonMask > 0) { sql += ' AND (g.season_mask & ?)<>0'; args.push(filter.seasonMask); }
      if (filter.search.trim()) {
        // instr 进行字面匹配，搜索中的 %、_ 和引号不变成通配符或 SQL。
        sql += ' AND instr(lower(g.name), lower(?))>0';
        args.push(filter.search.trim());
      }
      sql += ' ORDER BY g.updated_at DESC, g.id ASC';
      const rows = await store.querySql(sql, args);
      try {
        const garments: Garment[] = [];
        while (rows.goToNextRow()) { garments.push(mapGarment(rows)); }
        return garments;
      } finally { rows.close(); }
    });
  }

  async get(id: string, space: string): Promise<Garment> {
    return this.database.run(async (store: relationalStore.RdbStore): Promise<Garment> => {
      const rows = await store.querySql(`${SELECT_GARMENT} WHERE g.id=? AND g.space=?`, [id, space]);
      try {
        if (!rows.goToFirstRow()) { throw new AppError('NOT_FOUND', '这件衣物已不存在，请返回衣橱。'); }
        return mapGarment(rows);
      } finally { rows.close(); }
    });
  }

  async save(draft: GarmentDraft, photo?: PreparedPhoto): Promise<string> {
    validateDraft(draft);
    return this.database.transaction(async (tx: relationalStore.RdbStore): Promise<string> => {
      const id = draft.id || util.generateRandomUUID(true);
      let now = Date.now();
      if (draft.id) {
        const row = await tx.querySql('SELECT updated_at FROM garment WHERE id=? AND space=? AND version=?',
          [id, draft.space, draft.version]);
        try {
          if (!row.goToFirstRow()) { throw this.conflict(); }
          now = Math.max(now, row.getLong(0));
        } finally { row.close(); }
      }
      if (photo) {
        await tx.insert('media_asset', mediaValues(photo.original));
        await tx.insert('media_asset', mediaValues(photo.thumbnail));
      }
      const values: relationalStore.ValuesBucket = {
        name: draft.name.trim(), category: draft.category, color_group: draft.colorGroup,
        season_mask: draft.seasonMask, status: draft.status, updated_at: now, version: draft.version + 1
      };
      if (photo) {
        values.image_asset_id = photo.original.id;
        values.thumbnail_asset_id = photo.thumbnail.id;
      }
      if (draft.id) {
        const count = await tx.update(values, this.predicate(draft.space, new VersionedId(id, draft.version)));
        if (count !== 1) { throw this.conflict(); }
      } else {
        values.id = id;
        values.space = draft.space;
        values.created_at = now;
        values.version = 1;
        await tx.insert('garment', values);
      }
      return id;
    });
  }

  async hasImageHash(space: string, hash: string, excludeId: string): Promise<boolean> {
    return this.database.run(async (store: relationalStore.RdbStore): Promise<boolean> => {
      // 包括归档单品，但绝不跨 personal/demo 暗示另一空间中的素材。
      const rows = await store.querySql(`SELECT 1 FROM garment g
        JOIN media_asset m ON g.image_asset_id=m.id
        WHERE g.space=? AND m.sha256=? AND g.id<>? LIMIT 1`, [space, hash, excludeId]);
      try { return rows.rowCount > 0; } finally { rows.close(); }
    });
  }

  async batchChange(space: string, ids: VersionedId[], change: BatchChange): Promise<void> {
    validateBatch(ids, change);
    await this.database.transaction(async (tx: relationalStore.RdbStore): Promise<void> => {
      for (const id of ids) {
        const current = await tx.querySql('SELECT updated_at FROM garment WHERE id=? AND space=? AND version=?',
          [id.id, space, id.version]);
        let time = Date.now();
        try {
          if (!current.goToFirstRow()) { throw this.conflict(); }
          time = Math.max(time, current.getLong(0));
        } finally { current.close(); }
        const values: relationalStore.ValuesBucket = { version: id.version + 1, updated_at: time };
        if (change.status) { values.status = change.status; }
        if (change.category) { values.category = change.category; }
        if (change.seasonMask >= 0) { values.season_mask = change.seasonMask; }
        if (await tx.update(values, this.predicate(space, id)) !== 1) { throw this.conflict(); }
      }
    });
  }

  async deleteArchived(space: string, ids: VersionedId[]): Promise<void> {
    validateBatch(ids);
    await this.database.transaction(async (tx: relationalStore.RdbStore): Promise<void> => {
      for (const id of ids) {
        // M1 尚未实现历史快照脱敏，已有搭配引用时拒绝删除，而不是静默破坏历史。
        const refs = await tx.querySql('SELECT 1 FROM outfit_item WHERE garment_id=? LIMIT 1', [id.id]);
        try {
          if (refs.rowCount > 0) { throw new AppError('REFERENCED', '衣物仍被搭配引用，请先处理关联方案。'); }
        } finally { refs.close(); }
        const predicate = this.predicate(space, id).equalTo('status', 'archived');
        if (await tx.delete(predicate) !== 1) {
          throw new AppError('DELETE_CONFLICT', '只能永久删除已归档且未被修改的衣物，请刷新后重试。');
        }
      }
    });
  }

  async referencedPaths(): Promise<string[]> {
    await this.database.transaction(async (tx: relationalStore.RdbStore): Promise<void> => {
      // 保留其他领域的媒体引用；只清理衣物/缩略图，不触碰人物及云端资产。
      await tx.execute(`DELETE FROM media_asset WHERE kind IN ('garment','thumbnail')
        AND id NOT IN (SELECT image_asset_id FROM garment WHERE image_asset_id IS NOT NULL)
        AND id NOT IN (SELECT thumbnail_asset_id FROM garment WHERE thumbnail_asset_id IS NOT NULL)
        AND id NOT IN (SELECT cutout_asset_id FROM garment WHERE cutout_asset_id IS NOT NULL)
        AND id NOT IN (SELECT image_asset_id FROM person_pose)
        AND id NOT IN (SELECT input_asset_id FROM tryon_pose WHERE input_asset_id IS NOT NULL)
        AND id NOT IN (SELECT result_asset_id FROM tryon_pose WHERE result_asset_id IS NOT NULL)`);
    });
    // querySql 可能使用读连接，必须等上方 DELETE 提交后再取得清理快照。
    // 在同一事务中查询会读到旧引用，导致“已删除”图片仍留在沙箱。
    return this.database.run(async (store: relationalStore.RdbStore): Promise<string[]> => {
      const rows = await store.querySql('SELECT relative_path FROM media_asset');
      try {
        const paths: string[] = [];
        while (rows.goToNextRow()) { paths.push(rows.getString(0)); }
        return paths;
      } finally { rows.close(); }
    });
  }

  private predicate(space: string, id: VersionedId): relationalStore.RdbPredicates {
    return new relationalStore.RdbPredicates('garment').equalTo('id', id.id)
      .equalTo('space', space).equalTo('version', id.version);
  }

  private conflict(): AppError {
    return new AppError('VERSION_CONFLICT', '衣物已被修改，本次未覆盖任何内容。请返回后重新打开。');
  }
}
