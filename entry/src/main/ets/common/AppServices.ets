import { common } from '@kit.AbilityKit';
import { AppDatabase } from '../data/database/AppDatabase';
import { RdbGarmentRepository } from '../data/repositories/RdbGarmentRepository';
import { WardrobeService } from '../domain/usecases/WardrobeService';
import { PhotoStorage } from '../platform/media/PhotoStorage';

export class AppServices {
  private static instance?: AppServices;
  database: AppDatabase;
  wardrobe: WardrobeService;

  private constructor(context: common.Context) {
    this.database = new AppDatabase(context);
    this.wardrobe = new WardrobeService(new RdbGarmentRepository(this.database), new PhotoStorage(context));
  }

  static get(context: common.Context): AppServices {
    if (!AppServices.instance) {
      AppServices.instance = new AppServices(context.getApplicationContext());
    }
    return AppServices.instance;
  }
}
