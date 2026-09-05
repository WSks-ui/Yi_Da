import { errorMessage } from '../../../common/errors/AppError';
import { BatchChange, Garment, VersionedId } from '../../../domain/models/Garment';
import { WardrobeService } from '../../../domain/usecases/WardrobeService';

@ObservedV2
export class GarmentDetailViewModel {
  @Trace garment: Garment = new Garment();
  @Trace path: string = '';
  @Trace phase: string = 'loading';
  @Trace error: string = '';
  @Trace busy: boolean = false;
  private service?: WardrobeService;

  async load(service: WardrobeService, id: string, space: string): Promise<void> {
    this.service = service;
    this.phase = 'loading';
    this.error = '';
    try {
      this.garment = await service.repository.get(id, space);
      this.path = service.photos.absolute(this.garment.imagePath);
      this.phase = 'content';
    } catch (error) {
      this.error = errorMessage(error);
      this.phase = 'error';
    }
  }

  async changeStatus(status: string): Promise<boolean> {
    if (!this.service || this.busy) { return false; }
    this.busy = true;
    this.error = '';
    try {
      const change = new BatchChange();
      change.status = status;
      await this.service.batch(this.garment.space, [new VersionedId(this.garment.id, this.garment.version)], change);
      await this.load(this.service, this.garment.id, this.garment.space);
      return true;
    } catch (error) { this.error = errorMessage(error); return false; }
    finally { this.busy = false; }
  }

  async remove(): Promise<boolean> {
    if (!this.service || this.busy) { return false; }
    this.busy = true;
    try {
      await this.service.deleteArchived(this.garment.space, [new VersionedId(this.garment.id, this.garment.version)]);
      return true;
    } catch (error) { this.error = errorMessage(error); return false; }
    finally { this.busy = false; }
  }
}
