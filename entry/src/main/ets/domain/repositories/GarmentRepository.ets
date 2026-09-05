import { BatchChange, Garment, GarmentDraft, PreparedPhoto, VersionedId, WardrobeFilter } from '../models/Garment';

export interface GarmentRepository {
  list(filter: WardrobeFilter): Promise<Garment[]>;
  get(id: string, space: string): Promise<Garment>;
  save(draft: GarmentDraft, photo?: PreparedPhoto): Promise<string>;
  batchChange(space: string, ids: VersionedId[], change: BatchChange): Promise<void>;
  deleteArchived(space: string, ids: VersionedId[]): Promise<void>;
  referencedPaths(): Promise<string[]>;
}
