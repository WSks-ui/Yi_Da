import { errorMessage } from '../../../common/errors/AppError';
import { BatchChange, Garment, VersionedId, WardrobeFilter } from '../../../domain/models/Garment';
import { WardrobeService } from '../../../domain/usecases/WardrobeService';

@ObservedV2
export class WardrobeViewModel {
  @Trace items: Garment[] = [];
  @Trace phase: string = 'initial';
  @Trace error: string = '';
  @Trace notice: string = '';
  @Trace busy: boolean = false;
  @Trace search: string = '';
  @Trace category: string = '';
  @Trace status: string = '';
  @Trace seasonMask: number = 0;
  @Trace space: string = 'personal';
  @Trace selecting: boolean = false;
  @Trace selected: string[] = [];
  private generation: number = 0;
  private service?: WardrobeService;

  connect(service: WardrobeService): void { this.service = service; }

  async load(): Promise<void> {
    if (!this.service) { return; }
    const generation = ++this.generation;
    const filter = new WardrobeFilter();
    filter.space = this.space;
    filter.search = this.search;
    filter.category = this.category;
    filter.status = this.status;
    filter.seasonMask = this.seasonMask;
    this.phase = 'loading';
    this.error = '';
    try {
      const values = await this.service.repository.list(filter);
      // 快速切换筛选时，较慢的旧请求不能覆盖新的筛选结果。
      if (generation !== this.generation) { return; }
      this.items = values;
      this.selected = this.selected.filter((id: string) => values.some((value: Garment) => value.id === id));
      this.phase = values.length > 0 ? 'content' : 'empty';
      if (this.service.cleanupPending) {
        this.notice = '部分无引用图片清理待重试，可前往“我的”处理。';
      } else if (this.notice === '部分无引用图片清理待重试，可前往“我的”处理。') {
        this.notice = '';
      }
    } catch (error) {
      if (generation !== this.generation) { return; }
      this.error = errorMessage(error);
      this.phase = 'error';
    }
  }

  resetFilters(status: string = ''): void {
    this.search = '';
    this.category = '';
    this.status = status;
    this.seasonMask = 0;
    this.selected = [];
    this.selecting = false;
    this.notice = '';
    this.load();
  }

  async addSample(): Promise<void> {
    if (!this.service || this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      await this.service.addSample();
      this.notice = '示例素材：Lateiner / CC BY-SA 3.0，不属于个人衣物。';
      await this.load();
    } catch (error) { this.error = errorMessage(error); }
    finally { this.busy = false; }
  }

  toggle(id: string): void {
    if (this.busy || !this.items.some((item: Garment) => item.id === id)) { return; }
    if (!this.selected.includes(id) && this.selected.length >= 200) {
      this.error = '单次最多选择 200 件衣物。';
      return;
    }
    this.selected = this.selected.includes(id) ? this.selected.filter((value: string) => value !== id) : [...this.selected, id];
  }

  async batch(change: BatchChange): Promise<boolean> {
    if (!this.service || this.busy) { return false; }
    this.busy = true;
    this.error = '';
    try {
      await this.service.batch(this.space, this.selection(), change);
      this.selected = [];
      this.selecting = false;
      this.notice = '批量修改已保存';
      await this.load();
      return true;
    } catch (error) {
      this.error = errorMessage(error);
      return false;
    } finally { this.busy = false; }
  }

  async deleteSelected(): Promise<void> {
    if (!this.service || this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      await this.service.deleteArchived(this.space, this.selection());
      this.selected = [];
      this.selecting = false;
      this.notice = '衣物已永久删除';
      await this.load();
    } catch (error) { this.error = errorMessage(error); }
    finally { this.busy = false; }
  }

  private selection(): VersionedId[] {
    return this.items.filter((value: Garment) => this.selected.includes(value.id))
      .map((value: Garment) => new VersionedId(value.id, value.version));
  }
}
