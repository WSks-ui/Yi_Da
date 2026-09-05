import { AppServices } from '../common/AppServices';
import { errorMessage } from '../common/errors/AppError';
import { Garment, WardrobeFilter } from '../domain/models/Garment';
import { WardrobeViewModel } from './wardrobe/viewmodels/WardrobeViewModel';

@ObservedV2
export class ShellViewModel {
  @Trace phase: string = 'loading';
  @Trace error: string = '';
  @Trace total: number = 0;
  @Trace wearable: number = 0;
  @Trace laundry: number = 0;
  @Trace cleanupPending: boolean = false;
  @Trace statisticsReady: boolean = false;
  wardrobe: WardrobeViewModel = new WardrobeViewModel();
  services?: AppServices;

  async initialize(services: AppServices): Promise<void> {
    this.services = services;
    this.phase = 'loading';
    this.error = '';
    this.wardrobe.connect(services.wardrobe);
    try {
      await services.database.open();
      await services.wardrobe.initialize();
      await this.refresh();
      this.phase = 'content';
    } catch (error) {
      this.error = errorMessage(error);
      this.phase = 'error';
    }
  }

  async refresh(): Promise<void> {
    if (!this.services) { return; }
    try {
      const all = await this.services.wardrobe.repository.list(new WardrobeFilter());
      this.total = all.length;
      this.wearable = all.filter((value: Garment) => value.status === 'wearable').length;
      this.laundry = all.filter((value: Garment) => value.status === 'laundry').length;
      this.cleanupPending = this.services.wardrobe.cleanupPending;
      this.statisticsReady = true;
    } catch (error) {
      this.error = errorMessage(error);
      this.statisticsReady = false;
    }
    // 统计失败也应让列表进入自己的可重试状态，不能永远停留在 initial。
    await this.wardrobe.load();
  }

  async retryCleanup(): Promise<void> {
    if (this.services) {
      try {
        await this.services.wardrobe.initialize();
        this.cleanupPending = this.services.wardrobe.cleanupPending;
        await this.wardrobe.load();
        this.error = '';
      } catch (error) {
        this.error = errorMessage(error);
        this.cleanupPending = true;
      }
    }
  }
}
