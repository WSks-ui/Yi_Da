import { AppError, errorMessage } from '../../../common/errors/AppError';
import { GarmentDraft, PreparedPhoto } from '../../../domain/models/Garment';
import { WardrobeService } from '../../../domain/usecases/WardrobeService';

@ObservedV2
export class GarmentEditorViewModel {
  @Trace name: string = '';
  @Trace category: string = 'top';
  @Trace colorGroup: string = 'unknown';
  @Trace seasonMask: number = 0;
  @Trace status: string = 'wearable';
  @Trace imagePath: string = '';
  @Trace busy: boolean = false;
  @Trace loading: boolean = true;
  @Trace error: string = '';
  @Trace notice: string = '';
  @Trace dirty: boolean = false;
  @Trace loadFailed: boolean = false;
  @Trace duplicate: boolean = false;
  @Trace allowDuplicate: boolean = false;
  private draft: GarmentDraft = new GarmentDraft();
  private photo?: PreparedPhoto;
  private disposed: boolean = false;
  private service?: WardrobeService;
  private saveWork?: Promise<boolean>;
  private pickWork?: Promise<void>;

  async open(service: WardrobeService, id: string, space: string): Promise<void> {
    this.service = service;
    this.disposed = false;
    this.loading = true;
    this.loadFailed = false;
    this.error = '';
    this.draft.space = space;
    try {
      if (id) {
        const garment = await service.repository.get(id, space);
        if (this.disposed) { return; }
        this.draft = garment;
        this.name = garment.name;
        this.category = garment.category;
        this.colorGroup = garment.colorGroup;
        this.seasonMask = garment.seasonMask;
        this.status = garment.status;
        this.imagePath = service.photos.absolute(garment.imagePath);
      }
    } catch (error) {
      this.error = errorMessage(error);
      this.loadFailed = true;
    } finally { this.loading = false; }
  }

  pick(): Promise<void> {
    if (!this.service || this.disposed || this.busy) { return Promise.resolve(); }
    this.busy = true;
    this.error = '';
    this.notice = '';
    this.pickWork = this.choosePhoto();
    return this.pickWork;
  }

  private async choosePhoto(): Promise<void> {
    try {
      const uri = await this.service!.photos.pick();
      if (this.disposed) { return; }
      if (!uri) { this.notice = '已取消选图，原有内容保持不变。'; return; }
      const photo = await this.service!.photos.prepare(uri);
      if (this.disposed) { await this.discard(photo); return; }
      const old = this.photo;
      this.photo = photo;
      this.imagePath = this.service!.photos.absolute(photo.original.relativePath);
      this.dirty = true;
      this.duplicate = false;
      this.allowDuplicate = false;
      if (old) { await this.discard(old); }
    } catch (error) {
      this.error = `${errorMessage(error)} 也可以先不添加照片，手工保存衣物。`;
    } finally { this.busy = false; }
  }

  save(): Promise<boolean> {
    if (!this.service || this.disposed || this.busy || this.loading || this.loadFailed) { return Promise.resolve(false); }
    this.busy = true;
    this.error = '';
    this.saveWork = this.persist();
    return this.saveWork;
  }

  private async persist(): Promise<boolean> {
    this.draft.name = this.name;
    this.draft.category = this.category;
    this.draft.colorGroup = this.colorGroup;
    this.draft.seasonMask = this.seasonMask;
    this.draft.status = this.status;
    try {
      await this.service!.save(this.draft, this.photo, this.allowDuplicate);
      this.photo = undefined;
      this.dirty = false;
      return true;
    } catch (error) {
      if (error instanceof AppError && error.code === 'DUPLICATE_PHOTO') { this.duplicate = true; }
      this.error = errorMessage(error);
      return false;
    } finally { this.busy = false; }
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    // 等待迟到选图/解码完成清理后，再通知外层刷新；否则“我的”会遗漏清理失败提示。
    if (this.pickWork) { await this.pickWork; }
    // 保存期间销毁页面不能先删图片；等待事务结果后，只清理未转移给仓储的素材。
    if (this.saveWork) { await this.saveWork; }
    if (this.photo && this.service) {
      const photo = this.photo;
      this.photo = undefined;
      await this.discard(photo);
    }
  }

  private async discard(photo: PreparedPhoto): Promise<void> {
    try { await this.service!.photos.discard(photo); }
    catch (_) {
      // 取消或替换照片不等于文件必然删除成功；保留全局清理状态，交给“我的”重试。
      this.service!.cleanupPending = true;
      this.notice = '部分未保存照片暂未清理，请在“我的”中重试图片清理。';
    }
  }
}
