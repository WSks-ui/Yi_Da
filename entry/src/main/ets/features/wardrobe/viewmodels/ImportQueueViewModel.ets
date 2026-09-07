import { AppError, errorMessage } from '../../../common/errors/AppError';
import { GarmentDraft, PreparedPhoto } from '../../../domain/models/Garment';
import { MAX_IMPORT_PHOTOS } from '../../../domain/usecases/ImportPolicy';
import { validateDraft } from '../../../domain/usecases/GarmentRules';
import { WardrobeService } from '../../../domain/usecases/WardrobeService';

@ObservedV2
export class ImportItem {
  readonly id: string;
  sourceUri: string;
  photo?: PreparedPhoto;
  @Trace phase: string = 'pending';
  @Trace name: string = '';
  @Trace category: string = '';
  @Trace colorGroup: string = 'unknown';
  @Trace seasonMask: number = 0;
  @Trace status: string = 'wearable';
  @Trace imagePath: string = '';
  @Trace confirmed: boolean = false;
  @Trace duplicate: boolean = false;
  @Trace allowDuplicate: boolean = false;
  @Trace error: string = '';
  @Trace expanded: boolean = false;
  @Trace garmentId: string = '';

  constructor(id: string, uri: string) {
    this.id = id;
    this.sourceUri = uri;
  }

  draft(): GarmentDraft {
    const draft = new GarmentDraft();
    draft.name = this.name;
    draft.category = this.category;
    draft.colorGroup = this.colorGroup;
    draft.seasonMask = this.seasonMask;
    draft.status = this.status;
    return draft;
  }
}

@ObservedV2
export class ImportQueueViewModel {
  @Trace items: ImportItem[] = [];
  @Trace picking: boolean = false;
  @Trace processing: boolean = false;
  @Trace saving: boolean = false;
  @Trace closing: boolean = false;
  @Trace paused: boolean = false;
  @Trace error: string = '';
  @Trace notice: string = '';
  private service?: WardrobeService;
  private serial: number = 0;
  private disposed: boolean = false;
  private work?: Promise<void>;
  private saveWork?: Promise<void>;
  private closeWork?: Promise<void>;

  connect(service: WardrobeService): void { this.service = service; }

  hasUnfinished(): boolean {
    return this.items.some((item: ImportItem) => item.phase !== 'saved' && item.phase !== 'skipped');
  }

  savedCount(): number { return this.items.filter((item: ImportItem) => item.phase === 'saved').length; }

  readyCount(): number {
    return this.items.filter((item: ImportItem) => item.phase === 'ready' && item.confirmed).length;
  }

  async pick(): Promise<void> {
    if (!this.service || this.disposed || this.picking || this.processing || this.saving) { return; }
    this.error = '';
    const remaining = MAX_IMPORT_PHOTOS - this.items.length;
    if (remaining < 1) { this.error = '本次已达到 20 张上限，请先完成或结束本次导入。'; return; }
    this.picking = true;
    let addedCount = 0;
    try {
      const uris = await this.service.photos.pickMany(remaining);
      if (this.disposed) { return; }
      if (uris.length > remaining) { throw new AppError('IMPORT_LIMIT', '选图数量异常，请重新选择。'); }
      const seen = new Set(this.items.map((item: ImportItem) => item.sourceUri));
      const added: ImportItem[] = [];
      for (const uri of uris) {
        if (uri && !seen.has(uri)) {
          seen.add(uri);
          added.push(new ImportItem(`import-${++this.serial}`, uri));
        }
      }
      this.items = [...this.items, ...added];
      addedCount = added.length;
      this.notice = uris.length === 0 ? '已取消选图，当前队列保持不变。' :
        (added.length < uris.length ? '同一次导入中的重复选图已忽略。' : '');
    } catch (error) { if (!this.disposed) { this.error = errorMessage(error); } }
    finally { this.picking = false; }
    if (!this.disposed && addedCount > 0) { await this.resume(); }
  }

  resume(): Promise<void> {
    if (!this.service || this.disposed || this.processing || this.picking || this.saving) { return Promise.resolve(); }
    this.paused = false;
    this.processing = true;
    this.work = this.processItems();
    return this.work;
  }

  pause(): void {
    // 已开始的 ImageKit 调用不可假定能中断；当前项完成后停止领取下一项。
    this.paused = true;
  }

  private async processItems(): Promise<void> {
    try {
      for (const item of this.items) {
        if (this.disposed || this.paused) { break; }
        if (item.phase !== 'pending') { continue; }
        item.phase = 'processing';
        item.error = '';
        try {
          const photo = await this.service!.photos.prepare(item.sourceUri);
          item.photo = photo;
          if (this.disposed) { break; }
          item.imagePath = this.service!.photos.absolute(photo.thumbnail.relativePath);
          item.duplicate = await this.service!.repository.hasImageHash('personal', photo.original.sha256, '') ||
            this.items.some((other: ImportItem) => other !== item && other.phase !== 'skipped' &&
              other.photo?.original.sha256 === photo.original.sha256);
          item.phase = 'ready';
        } catch (error) {
          item.phase = 'failed';
          item.imagePath = '';
          item.error = errorMessage(error);
          if (item.photo) { await this.discard(item); }
        }
      }
    } finally { this.processing = false; }
  }

  async retry(item: ImportItem): Promise<void> {
    if (this.disposed || this.processing || this.saving || this.picking || item.phase !== 'failed') { return; }
    item.phase = 'pending';
    await this.resume();
  }

  async skip(item: ImportItem): Promise<void> {
    if (this.disposed || this.saving || item.phase === 'processing' || item.phase === 'saved') { return; }
    item.phase = 'skipped';
    item.confirmed = false;
    item.imagePath = '';
    if (item.photo) { await this.discard(item); }
  }

  saveConfirmed(): Promise<void> {
    if (!this.service || this.disposed || this.saving || this.processing || this.picking) { return Promise.resolve(); }
    this.saving = true;
    this.error = '';
    // 表单会冻结，但用独立 draft 快照明确本次提交内容，不受异步 UI 事件改写。
    this.saveWork = this.saveItems();
    return this.saveWork;
  }

  private async saveItems(): Promise<void> {
    try {
      const selected = this.items.filter((item: ImportItem) => item.phase === 'ready' && item.confirmed);
      if (selected.length === 0) { this.error = '请先确认要保存的衣物。'; return; }
      for (const item of selected) {
        if (this.disposed) { break; }
        item.error = '';
        try {
          const draft = item.draft();
          validateDraft(draft);
          if (!item.photo) { throw new AppError('PHOTO_MISSING', '照片尚未准备完成，请重试。'); }
          if (item.duplicate && !item.allowDuplicate) {
            throw new AppError('DUPLICATE_PHOTO', '照片可能重复，请明确确认后再保存。');
          }
          item.phase = 'saving';
          item.garmentId = await this.service!.save(draft, item.photo, item.allowDuplicate);
          // 先转移媒体所有权，再响应页面关闭；已提交照片永远不能由取消路径删除。
          item.photo = undefined;
          item.sourceUri = '';
          item.phase = 'saved';
          item.confirmed = false;
        } catch (error) {
          item.phase = 'ready';
          item.error = errorMessage(error);
          if (error instanceof AppError && error.code === 'DUPLICATE_PHOTO') { item.duplicate = true; }
        }
      }
      this.notice = `已保存 ${this.savedCount()} 件；未成功的项目仍可修改或重试。`;
    } finally { this.saving = false; }
  }

  dispose(): Promise<void> {
    if (this.closeWork) { return this.closeWork; }
    this.disposed = true;
    this.closing = true;
    this.paused = true;
    this.closeWork = this.close();
    return this.closeWork;
  }

  private async close(): Promise<void> {
    // 即使系统在保存中销毁页面，也要等本次提交收尾，避免删掉刚关联数据库的照片。
    if (this.work) { await this.work; }
    if (this.saveWork) { await this.saveWork; }
    for (const item of this.items) {
      if (item.photo) { await this.discard(item); }
      item.sourceUri = '';
    }
    this.closing = false;
  }

  private async discard(item: ImportItem): Promise<void> {
    const photo = item.photo;
    item.photo = undefined;
    if (!photo || !this.service) { return; }
    try { await this.service.photos.discard(photo); }
    catch (_) {
      this.service.cleanupPending = true;
      this.error = '部分未保存照片暂未清理，请在“我的”中重试图片清理。';
    }
  }
}
