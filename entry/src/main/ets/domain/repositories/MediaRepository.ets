import { PreparedPhoto } from '../models/Garment';

export interface MediaRepository {
  initialize(): Promise<void>;
  pick(): Promise<string>;
  prepare(uri: string): Promise<PreparedPhoto>;
  prepareSample(): Promise<PreparedPhoto>;
  absolute(relativePath: string): string;
  release(photo: PreparedPhoto): void;
  discard(photo: PreparedPhoto): Promise<void>;
  collect(references: string[]): Promise<void>;
}
