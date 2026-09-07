import { abilityDelegatorRegistry } from '@kit.TestKit';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { AppDatabase } from '../../../main/ets/data/database/AppDatabase';
import { RdbGarmentRepository } from '../../../main/ets/data/repositories/RdbGarmentRepository';
import { BatchChange, GarmentDraft, VersionedId, WardrobeFilter } from '../../../main/ets/domain/models/Garment';
import { PhotoStorage } from '../../../main/ets/platform/media/PhotoStorage';
import { WardrobeService } from '../../../main/ets/domain/usecases/WardrobeService';
import { ImportQueueViewModel } from '../../../main/ets/features/wardrobe/viewmodels/ImportQueueViewModel';
import { validatePickLimit } from '../../../main/ets/domain/usecases/ImportPolicy';

// 错误文件无法放进真实图库；此适配器只在故障注入测试中重放选图列表。
// 实际 PhotoViewPicker 端到端证据由独立页面流程取得，不能拿此替身充数。
class ReplayPhotoStorage extends PhotoStorage {
  selectedPaths: string[] = [];

  async pickMany(limit: number): Promise<string[]> {
    validatePickLimit(limit);
    return this.selectedPaths.slice(0, limit);
  }
}

export default function wardrobeTest(): void {
  describe('WardrobeRuntime', () => {
    let context: common.Context;
    let database: AppDatabase;
    let repository: RdbGarmentRepository;
    let photos: PhotoStorage;
    let service: WardrobeService;
    let databaseName = '';
    let namespace = '';
    let firstId = '';
    let secondId = '';

    beforeAll(async () => {
      context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry');
      databaseName = `test-${util.generateRandomUUID(true)}.db`;
      namespace = `test-${util.generateRandomUUID(true)}`;
      database = new AppDatabase(context, databaseName);
      repository = new RdbGarmentRepository(database);
      photos = new PhotoStorage(context, namespace);
      service = new WardrobeService(repository, photos);
      await database.open();
      await service.initialize();
    });

    afterAll(async () => {
      if (database) { await database.close(); }
      // 只删除随机测试库；测试图片位于独立 test-UUID 目录，不扫描真实个人衣橱。
      if (context && databaseName) { await relationalStore.deleteRdbStore(context, databaseName); }
      if (context && namespace) { await fs.rmdir(`${context.filesDir}/${namespace}`); }
    });

    it('manualSaveReopenAndRead', 0, async () => {
      const draft = new GarmentDraft();
      draft.name = '运行时测试衬衫';
      firstId = await repository.save(draft);
      await database.close();
      const item = await repository.get(firstId, 'personal');
      expect(item.name).assertEqual('运行时测试衬衫');
      expect(item.version).assertEqual(1);
      expect(item.imagePath).assertEqual('');
      expect(item.imageAssetId).assertEqual('');
    });

    it('foreignKeyReallyRejectsMissingMedia', 0, async () => {
      let rejected = false;
      try {
        await database.transaction(async (store: relationalStore.RdbStore): Promise<void> => {
          await store.executeSql("UPDATE garment SET image_asset_id='missing' WHERE id=?", [firstId]);
        });
      } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
      expect((await repository.get(firstId, 'personal')).imageAssetId).assertEqual('');
    });

    it('failedMigrationTransactionPreservesVersionAndRows', 0, async () => {
      let rejected = false;
      try {
        await database.transaction(async (store: relationalStore.RdbStore): Promise<void> => {
          await store.executeSql('CREATE TABLE migration_probe(id TEXT)');
          await store.executeSql('PRAGMA user_version=2');
          await store.executeSql('INVALID MIGRATION SQL');
        });
      } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
      await database.run(async (store: relationalStore.RdbStore): Promise<void> => {
        expect(store.version).assertEqual(1);
        const rows = await store.querySql("SELECT name FROM sqlite_master WHERE name='migration_probe'");
        try { expect(rows.rowCount).assertEqual(0); } finally { rows.close(); }
      });
      expect((await repository.get(firstId, 'personal')).name).assertEqual('运行时测试衬衫');
    });

    it('staleVersionDoesNotOverwrite', 0, async () => {
      const current = await repository.get(firstId, 'personal');
      const stale = await repository.get(firstId, 'personal');
      current.name = '已编辑测试衬衫';
      await repository.save(current);
      stale.name = '不应覆盖';
      await expect(repository.save(stale)).assertPromiseIsRejected();
      expect((await repository.get(firstId, 'personal')).name).assertEqual('已编辑测试衬衫');
    });

    it('batchFailureRollsBackEveryItem', 0, async () => {
      const draft = new GarmentDraft();
      draft.name = '第二件测试衣物';
      secondId = await repository.save(draft);
      const current = await repository.get(firstId, 'personal');
      const change = new BatchChange();
      change.status = 'laundry';
      await expect(repository.batchChange('personal',
        [new VersionedId(firstId, current.version), new VersionedId(secondId, 999)], change)).assertPromiseIsRejected();
      expect((await repository.get(firstId, 'personal')).status).assertEqual('wearable');
      expect((await repository.get(secondId, 'personal')).status).assertEqual('wearable');
      expect((await repository.get(firstId, 'personal')).version).assertEqual(current.version);
    });

    it('batchCategorySeasonAndStatusArePersisted', 0, async () => {
      const first = await repository.get(firstId, 'personal');
      const second = await repository.get(secondId, 'personal');
      const change = new BatchChange();
      change.status = 'laundry';
      change.category = 'outerwear';
      change.seasonMask = 9;
      await repository.batchChange('personal',
        [new VersionedId(first.id, first.version), new VersionedId(second.id, second.version)], change);
      const filter = new WardrobeFilter();
      filter.status = 'laundry';
      filter.category = 'outerwear';
      filter.seasonMask = 8;
      expect((await repository.list(filter)).length).assertEqual(2);
      filter.seasonMask = 2;
      expect((await repository.list(filter)).length).assertEqual(0);
    });

    it('spacesAndLiteralSearchAreIsolated', 0, async () => {
      const draft = new GarmentDraft();
      draft.space = 'demo';
      draft.name = "QA 100%_'";
      const id = await repository.save(draft);
      const filter = new WardrobeFilter();
      filter.search = "%_'";
      expect((await repository.list(filter)).length).assertEqual(0);
      filter.space = 'demo';
      expect((await repository.list(filter)).length).assertEqual(1);
      await expect(repository.get(id, 'personal')).assertPromiseIsRejected();
    });

    it('archiveRestoreAndPermanentDelete', 0, async () => {
      let value = await repository.get(secondId, 'personal');
      const change = new BatchChange();
      change.status = 'archived';
      await repository.batchChange('personal', [new VersionedId(value.id, value.version)], change);
      const filter = new WardrobeFilter();
      filter.status = 'archived';
      expect((await repository.list(filter)).length).assertEqual(1);
      value = await repository.get(secondId, 'personal');
      change.status = 'stored';
      await repository.batchChange('personal', [new VersionedId(value.id, value.version)], change);
      value = await repository.get(secondId, 'personal');
      await expect(repository.deleteArchived('personal', [new VersionedId(value.id, value.version)])).assertPromiseIsRejected();
      change.status = 'archived';
      await repository.batchChange('personal', [new VersionedId(value.id, value.version)], change);
      value = await repository.get(secondId, 'personal');
      await repository.deleteArchived('personal', [new VersionedId(value.id, value.version)]);
      await expect(repository.get(secondId, 'personal')).assertPromiseIsRejected();
    });

    it('mediaNormalizeHashThumbnailSaveAndReopen', 0, async () => {
      const filePath = `${context.filesDir}/${namespace}/fixture.png`;
      // QA 像素矩阵不是服装样例，不进入个人衣橱；只验证真实 ImageKit 编解码路径。
      const pixels = new Uint8Array(64 * 32 * 4);
      pixels.fill(255);
      const pixel = await image.createPixelMap(pixels.buffer, {
        size: { width: 64, height: 32 }, pixelFormat: image.PixelMapFormat.RGBA_8888,
        srcPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const packer = image.createImagePacker();
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { await packer.packToFile(pixel, file.fd, { format: 'image/png', quality: 100 }); }
      finally { await fs.close(file); await packer.release(); await pixel.release(); }
      const prepared = await photos.prepare(filePath);
      expect(prepared.original.sha256.length).assertEqual(64);
      expect(prepared.thumbnail.width <= 384).assertTrue();
      const draft = new GarmentDraft();
      draft.name = 'QA像素图片，非服装样例';
      const id = await service.save(draft, prepared);
      expect(service.cleanupPending).assertFalse();
      await fs.unlink(filePath);
      await database.close();
      const value = await repository.get(id, 'personal');
      expect(await fs.access(photos.absolute(value.imagePath))).assertTrue();
      expect(await fs.access(photos.absolute(value.thumbnailPath))).assertTrue();
      expect(value.imagePath.startsWith('media/')).assertTrue();
      const change = new BatchChange();
      change.status = 'archived';
      await service.batch('personal', [new VersionedId(value.id, value.version)], change);
      await service.deleteArchived('personal', [new VersionedId(value.id, value.version + 1)]);
      expect(service.cleanupPending).assertFalse();
      expect((await repository.referencedPaths()).includes(value.imagePath)).assertFalse();
      expect(await fs.access(photos.absolute(value.imagePath))).assertFalse();
      expect(await fs.access(photos.absolute(value.thumbnailPath))).assertFalse();
    });

    it('invalidImageKeepsExistingDataAndCleansStaging', 0, async () => {
      const path = `${context.filesDir}/${namespace}/fake.jpg`;
      const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      try { await fs.write(file.fd, 'not-a-jpeg-image'); } finally { await fs.close(file); }
      await expect(photos.prepare(path)).assertPromiseIsRejected();
      await fs.unlink(path);
      expect((await fs.listFile(`${context.filesDir}/${namespace}/staging`)).length).assertEqual(0);
      expect((await repository.get(firstId, 'personal')).name).assertEqual('已编辑测试衬衫');
    });

    it('allExifOrientationsNormalizeAndMetadataIsRemoved', 0, async () => {
      const expected: number[][] = [
        [0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
        [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]
      ];
      const colors: number[][] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]];
      for (let orientation = 1; orientation <= 8; orientation++) {
        const path = `${context.filesDir}/${namespace}/orientation-${orientation}.jpg`;
        const bytes = new Uint8Array(64 * 32 * 4);
        for (let y = 0; y < 32; y++) {
          for (let x = 0; x < 64; x++) {
            const color = colors[(y >= 16 ? 2 : 0) + (x >= 32 ? 1 : 0)];
            const offset = (y * 64 + x) * 4;
            bytes[offset] = color[0]; bytes[offset + 1] = color[1]; bytes[offset + 2] = color[2]; bytes[offset + 3] = 255;
          }
        }
        const pixels = await image.createPixelMap(bytes.buffer, {
          size: { width: 64, height: 32 }, pixelFormat: image.PixelMapFormat.RGBA_8888,
          srcPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        const packer = image.createImagePacker();
        const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { await packer.packToFile(pixels, file.fd, { format: 'image/jpeg', quality: 100 }); }
        finally { await fs.close(file); await packer.release(); await pixels.release(); }
        const input = image.createImageSource(path);
        try {
          await input.modifyImageProperty(image.PropertyKey.ORIENTATION, `${orientation}`);
          await input.modifyImageProperty(image.PropertyKey.ARTIST, 'QA_METADATA_MUST_BE_REMOVED');
        } finally { await input.release(); }
        const prepared = await photos.prepare(path);
        try {
          const width = orientation >= 5 ? 32 : 64;
          const height = orientation >= 5 ? 64 : 32;
          expect(prepared.original.width).assertEqual(width);
          expect(prepared.original.height).assertEqual(height);
          const output = image.createImageSource(photos.absolute(prepared.original.relativePath));
          try {
            expect(await output.getImageProperty(image.PropertyKey.ARTIST, { index: 0, defaultValue: 'absent' })).assertEqual('absent');
            const result = await output.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
            try {
              const rgba = new ArrayBuffer(width * height * 4);
              await result.readPixelsToBuffer(rgba);
              const data = new Uint8Array(rgba);
              const points = [[4, 4], [width - 5, 4], [4, height - 5], [width - 5, height - 5]];
              for (let index = 0; index < 4; index++) {
                const expectedColor = colors[expected[orientation - 1][index]];
                const offset = (points[index][1] * width + points[index][0]) * 4;
                for (let channel = 0; channel < 3; channel++) {
                  if (Math.abs(data[offset + channel] - expectedColor[channel]) >= 40) {
                    throw new Error(`QA orientation=${orientation}, corner=${index}, channel=${channel}, actual=${data[offset + channel]}, expected=${expectedColor[channel]}`);
                  }
                }
              }
            } finally { await result.release(); }
          } finally { await output.release(); }
        } finally { await photos.discard(prepared); await fs.unlink(path); }
      }
    });

    it('realFileQueueKeepsFourGoodItemsAndReopensSavedRecords', 0, async () => {
      const replay = new ReplayPhotoStorage(context, namespace);
      const queueService = new WardrobeService(repository, replay);
      const queue = new ImportQueueViewModel();
      queue.connect(queueService);
      const content = await context.resourceManager.getRawFileContent('demo/tshirt.jpg');
      const paths: string[] = [];
      try {
        for (let index = 0; index < 5; index++) {
          const path = `${context.filesDir}/${namespace}/queue-${index}.jpg`;
          const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try {
            const data = index === 2 ? new util.TextEncoder().encodeInto('not-a-real-jpeg') : content;
            const bytes = new ArrayBuffer(data.byteLength);
            new Uint8Array(bytes).set(data);
            let offset = 0;
            while (offset < bytes.byteLength) {
              const written = await fs.write(file.fd, bytes.slice(offset));
              if (written < 1) { throw new Error('QA write failed'); }
              offset += written;
            }
          } finally { await fs.close(file); }
          paths.push(path);
        }
        replay.selectedPaths = paths;
        await queue.pick();
        expect(queue.items.filter((item) => item.phase === 'ready').length).assertEqual(4);
        expect(queue.items[2].phase).assertEqual('failed');
        for (let index = 0; index < queue.items.length; index++) {
          const item = queue.items[index];
          if (item.phase !== 'ready') { continue; }
          item.name = `QA_Queue_Runtime_${index}`;
          item.category = 'top';
          item.confirmed = true;
          item.allowDuplicate = true;
        }
        await queue.saveConfirmed();
        expect(queue.savedCount()).assertEqual(4);
        expect(queue.items[2].phase).assertEqual('failed');
        await queue.dispose();
        await database.close();
        const filter = new WardrobeFilter();
        filter.search = 'QA_Queue_Runtime_';
        const saved = await repository.list(filter);
        expect(saved.length).assertEqual(4);
        for (const garment of saved) {
          expect(await fs.access(replay.absolute(garment.imagePath))).assertTrue();
          expect(await fs.access(replay.absolute(garment.thumbnailPath))).assertTrue();
        }
        const ids = saved.map((garment) => new VersionedId(garment.id, garment.version));
        const archive = new BatchChange();
        archive.status = 'archived';
        await queueService.batch('personal', ids, archive);
        await queueService.deleteArchived('personal', ids.map((id) => new VersionedId(id.id, id.version + 1)));
        expect(queueService.cleanupPending).assertFalse();
      } finally {
        await queue.dispose();
        for (const path of paths) { if (await fs.access(path)) { await fs.unlink(path); } }
      }
    });

    it('duplicateHashIsSpaceScopedAndOverrideIsExplicit', 0, async () => {
      const firstPhoto = await photos.prepareSample();
      const draft = new GarmentDraft();
      draft.name = 'QA_Hash_First';
      const id = await service.save(draft, firstPhoto);
      expect(await repository.hasImageHash('personal', firstPhoto.original.sha256, '')).assertTrue();
      expect(await repository.hasImageHash('personal', firstPhoto.original.sha256, id)).assertFalse();
      expect(await repository.hasImageHash('demo', firstPhoto.original.sha256, '')).assertFalse();
      const secondPhoto = await photos.prepareSample();
      draft.name = 'QA_Hash_Second';
      await expect(service.save(draft, secondPhoto)).assertPromiseIsRejected();
      expect(await fs.access(photos.absolute(secondPhoto.original.relativePath))).assertTrue();
      const secondId = await service.save(draft, secondPhoto, true);
      const archive = new BatchChange();
      archive.status = 'archived';
      await service.batch('personal', [new VersionedId(id, 1), new VersionedId(secondId, 1)], archive);
      // 已归档衣物也必须提示相同照片，不能把归档当作防重复的漏洞。
      expect(await repository.hasImageHash('personal', firstPhoto.original.sha256, '')).assertTrue();
      await service.deleteArchived('personal', [new VersionedId(id, 2), new VersionedId(secondId, 2)]);
    });

    it('allSeasonMasksPersistWithoutChangingOtherFields', 0, async () => {
      for (let mask = 0; mask < 16; mask++) {
        const current = await repository.get(firstId, 'personal');
        const change = new BatchChange();
        change.seasonMask = mask;
        await service.batch('personal', [new VersionedId(current.id, current.version)], change);
        const changed = await repository.get(firstId, 'personal');
        expect(changed.seasonMask).assertEqual(mask);
        expect(changed.name).assertEqual(current.name);
        expect(changed.status).assertEqual(current.status);
        expect(changed.category).assertEqual(current.category);
        expect(changed.version).assertEqual(current.version + 1);
      }
    });

    it('licensedSamplePhotoUsesSeparateDemoSpace', 0, async () => {
      const prepared = await photos.prepareSample();
      const draft = new GarmentDraft();
      draft.space = 'demo';
      draft.name = '独立示例测试';
      const id = await service.save(draft, prepared);
      expect((await repository.get(id, 'demo')).imagePath.length > 0).assertTrue();
      await expect(repository.get(id, 'personal')).assertPromiseIsRejected();
      expect(service.cleanupPending).assertFalse();
    });

    it('newerDatabaseIsNeverRebuilt', 0, async () => {
      await database.run(async (store: relationalStore.RdbStore): Promise<void> => {
        await store.executeSql('PRAGMA user_version=2');
      });
      await database.close();
      await expect(database.open()).assertPromiseIsRejected();
      const store = await relationalStore.getRdbStore(context, {
        name: databaseName, securityLevel: relationalStore.SecurityLevel.S3
      });
      try {
        expect(store.version).assertEqual(2);
        const rows = await store.querySql('SELECT name FROM garment WHERE id=?', [firstId]);
        try { expect(rows.rowCount).assertEqual(1); } finally { rows.close(); }
        await store.executeSql('PRAGMA user_version=1');
      } finally { await store.close(); }
    });
  });
}
