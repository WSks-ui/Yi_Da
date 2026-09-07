import { BatchChange, GarmentDraft, PreparedPhoto, VersionedId, WardrobeFilter } from '../models/Garment';
import { GarmentRepository } from '../repositories/GarmentRepository';
import { MediaRepository } from '../repositories/MediaRepository';
import { AppError } from '../../common/errors/AppError';
import { validateDraft } from './GarmentRules';

export class WardrobeService {
  private queue: Promise<void> = Promise.resolve();
  cleanupPending: boolean = false;
  repository: GarmentRepository;
  photos: MediaRepository;

  constructor(repository: GarmentRepository, photos: MediaRepository) {
    this.repository = repository;
    this.photos = photos;
  }

  initialize(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.photos.initialize();
      await this.cleanup();
    });
  }

  save(draft: GarmentDraft, photo?: PreparedPhoto, allowDuplicate: boolean = false): Promise<string> {
    return this.enqueue(async (): Promise<string> => {
      validateDraft(draft);
      // 在串行提交队列内再次检查，防止两项同时确认后都绕过重复提示。
      // 仅比较标准化文件摘要，不宣称能识别视觉相似照片。
      if (photo && !allowDuplicate &&
        await this.repository.hasImageHash(draft.space, photo.original.sha256, draft.id)) {
        throw new AppError('DUPLICATE_PHOTO', '当前衣橱已有相同照片，请确认是否仍要添加。');
      }
      const id = await this.repository.save(draft, photo);
      if (photo) { this.photos.release(photo); }
      await this.cleanup();
      return id;
    });
  }

  batch(space: string, ids: VersionedId[], change: BatchChange): Promise<void> {
    return this.enqueue(async (): Promise<void> => { await this.repository.batchChange(space, ids, change); });
  }

  deleteArchived(space: string, ids: VersionedId[]): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.repository.deleteArchived(space, ids);
      await this.cleanup();
    });
  }

  addSample(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const filter = new WardrobeFilter();
      filter.space = 'demo';
      if ((await this.repository.list(filter)).length > 0) { return; }
      const photo = await this.photos.prepareSample();
      const draft = new GarmentDraft();
      draft.name = '示例 · 浅色印花 T 恤';
      draft.space = 'demo';
      draft.colorGroup = 'white';
      draft.seasonMask = 3;
      try {
        await this.repository.save(draft, photo);
        this.photos.release(photo);
      } catch (error) {
        await this.photos.discard(photo);
        throw error as Error;
      }
      await this.cleanup();
    });
  }

  private async cleanup(): Promise<void> {
    try {
      await this.photos.collect(await this.repository.referencedPaths());
      this.cleanupPending = false;
    } catch (_) {
      // 数据事务已提交时，文件清理失败不能伪报“保存失败”诱发重复录入。
      // 未引用的文件下一次启动/保存时重试；UI 必须持续提示清理未完成。
      this.cleanupPending = true;
    }
  }

  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    // 文件引用快照与提交串行化，防止清理器删除刚刚提交的照片。
    const result = this.queue.then(work);
    this.queue = result.then(() => {}, () => {});
    return result;
  }
}
