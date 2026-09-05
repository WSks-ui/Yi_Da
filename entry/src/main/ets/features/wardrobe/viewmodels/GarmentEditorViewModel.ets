import { errorMessage } from '../../../common/errors/AppError';
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
  private draft: GarmentDraft = new GarmentDraft();
  private photo?: PreparedPhoto;
  private disposed: boolean = false;
  private service?: WardrobeService;

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

  async pick(): Promise<void> {
    if (!this.service || this.busy) { return; }
    this.busy = true;
    this.error = '';
    this.notice = '';
    try {
      const uri = await this.service.photos.pick();
      if (!uri) { this.notice = '已取消选图，原有内容保持不变。'; return; }
      const photo = await this.service.photos.prepare(uri);
      if (this.disposed) { await this.service.photos.discard(photo); return; }
      const old = this.photo;
      this.photo = photo;
      this.imagePath = this.service.photos.absolute(photo.original.relativePath);
      this.dirty = true;
      if (old) { await this.service.photos.discard(old); }
    } catch (error) {
      this.error = `${errorMessage(error)} 也可以先不添加照片，手工保存衣物。`;
    } finally { this.busy = false; }
  }

  async save(): Promise<boolean> {
    if (!this.service || this.busy || this.loading || this.loadFailed) { return false; }
    this.busy = true;
    this.error = '';
    this.draft.name = this.name;
    this.draft.category = this.category;
    this.draft.colorGroup = this.colorGroup;
    this.draft.seasonMask = this.seasonMask;
    this.draft.status = this.status;
    try {
      await this.service.save(this.draft, this.photo);
      this.photo = undefined;
      this.dirty = false;
      return true;
    } catch (error) {
      this.error = errorMessage(error);
      return false;
    } finally { this.busy = false; }
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    if (this.photo && this.service) {
      const photo = this.photo;
      this.photo = undefined;
      try { await this.service.photos.discard(photo); } catch (_) {}
    }
  }
}
