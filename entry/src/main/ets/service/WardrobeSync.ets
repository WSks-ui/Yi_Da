// 衣橱同步的纯数据层。
//
// 这里不直接访问文件、网络或分布式数据 Kit。应用层可以把序列化后的信封
// 交给 Preferences、分布式数据或后端适配器；离线时 InMemory 传输层仍会真实
// 保留待发送消息，Noop 传输层则明确报告“未排队”，不会伪装成已同步。

export const SYNC_SCHEMA_VERSION: number = 1;

export type SyncPayload = Record<string, Object>;

export interface SyncEnvelope<T extends Object = SyncPayload> {
  deviceId: string;
  schemaVersion: number;
  revision: number;
  updatedAt: string;
  snapshotHash: string;
  snapshot: T;
}

export type SyncMergeStatus = 'applied' | 'duplicate' | 'stale' | 'conflict' | 'rejected';
export type SyncConflictResolution = 'remote' | 'local' | 'manual';

export interface SyncConflict {
  reason: string;
  localRevision: number;
  remoteRevision: number;
  localUpdatedAt: string;
  remoteUpdatedAt: string;
  localHash: string;
  remoteHash: string;
  resolution: SyncConflictResolution;
}

export interface SyncMergeResult<T extends Object = SyncPayload> {
  status: SyncMergeStatus;
  accepted: boolean;
  message: string;
  snapshot: T;
  envelope: SyncEnvelope<T>;
  conflict?: SyncConflict;
}

export interface SyncValidationResult<T extends Object = SyncPayload> {
  valid: boolean;
  envelope?: SyncEnvelope<T>;
  error: string;
}

export interface SyncTransportReceipt {
  accepted: boolean;
  queued: boolean;
  online: boolean;
  messageId: string;
  message: string;
}

export const SYNC_PACKAGE_FORMAT: string = 'yida-wardrobe-sync';
export const SYNC_PACKAGE_VERSION: number = 1;

// 同步包只是一段可分享/可导入的文本。应用层可以把它交给系统分享或文件选择器，
// 这里不直接读写应用私有目录，也不把“导出完成”描述成“跨设备已同步”。
export interface SyncPackage<T extends Object = SyncPayload> {
  format: string;
  packageVersion: number;
  exportedAt: string;
  envelope: SyncEnvelope<T>;
  continuationPayload: string;
}

// 传输层只负责保存待发送信封和取回收到的信封，具体实现可以替换成分布式数据 Kit。
export interface LocalSyncTransport<T extends Object = SyncPayload> {
  enqueue(envelope: SyncEnvelope<T>): Promise<SyncTransportReceipt> | SyncTransportReceipt;
  drain(): Promise<SyncEnvelope<T>[]> | SyncEnvelope<T>[];
}

export interface SyncCoordinator<T extends Object = SyncPayload> {
  createEnvelope(snapshot: T, revision: number, updatedAt?: string): SyncEnvelope<T>;
  publish(snapshot: T, revision: number, updatedAt?: string): Promise<SyncTransportReceipt>;
  merge(envelope: SyncEnvelope<T>): SyncMergeResult<T>;
  receive(envelopes?: SyncEnvelope<T>[]): Promise<SyncMergeResult<T>[]>;
  currentEnvelope(): SyncEnvelope<T>;
  pending(): SyncEnvelope<T>[];
}

function isObject(value: Object | null | undefined): boolean {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value);
}

function clone<T extends Object>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function canonical(value: Object | null | undefined): string {
  if (value === null) { return 'null'; }
  if (value === undefined) { return 'undefined'; }
  if (typeof value === 'string') { return JSON.stringify(value); }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) { throw new Error('同步数据包含非法数字'); }
    return String(value);
  }
  if (typeof value === 'boolean') { return value ? 'true' : 'false'; }
  if (Array.isArray(value)) {
    return '[' + value.map((item: Object) => canonical(item)).join(',') + ']';
  }
  const record: Record<string, Object> = value as Record<string, Object>;
  const keys: string[] = Object.keys(record).sort();
  const fields: string[] = [];
  for (const key of keys) {
    fields.push(JSON.stringify(key) + ':' + canonical(record[key]));
  }
  return '{' + fields.join(',') + '}';
}

// 使用纯 ArkTS 可执行的 FNV-1a，避免为了计算快照 hash 引入平台或网络依赖。
// 该 hash 用于检测重复/损坏/冲突，不是安全签名，不能替代鉴权或加密。
export function computeSnapshotHash(snapshot: Object): string {
  const text: string = canonical(snapshot);
  let hash: number = 2166136261;
  for (let index: number = 0; index < text.length; index++) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

function isValidTimestamp(value: string): boolean {
  if (typeof value !== 'string' || value.length === 0) { return false; }
  return Number.isFinite(new Date(value).getTime());
}

function messageIdOf<T extends Object>(envelope: SyncEnvelope<T>): string {
  return envelope.deviceId + ':' + String(envelope.revision) + ':' + envelope.snapshotHash;
}

function validateEnvelopeShape<T extends Object>(value: Object): string {
  const envelope: Record<string, Object> = value as Record<string, Object>;
  if (typeof envelope.deviceId !== 'string' || envelope.deviceId.length === 0) {
    return '同步信封缺少 deviceId';
  }
  if (envelope.schemaVersion !== SYNC_SCHEMA_VERSION) {
    return '不支持的同步 schemaVersion';
  }
  if (typeof envelope.revision !== 'number' || !Number.isInteger(envelope.revision) || envelope.revision < 0) {
    return '同步 revision 必须是非负整数';
  }
  if (!isValidTimestamp(envelope.updatedAt as string)) {
    return '同步 updatedAt 不是有效时间';
  }
  if (typeof envelope.snapshotHash !== 'string' || envelope.snapshotHash.length === 0) {
    return '同步信封缺少 snapshotHash';
  }
  if (!isObject(envelope.snapshot)) { return '同步信封缺少对象 snapshot'; }
  let actualHash: string = '';
  try {
    actualHash = computeSnapshotHash(envelope.snapshot);
  } catch (error) {
    return (error as Error).message || '同步 snapshot 无法计算 hash';
  }
  if (actualHash !== envelope.snapshotHash) {
    return 'snapshotHash 与 snapshot 内容不一致';
  }
  return '';
}

export function validateSyncEnvelope<T extends Object = SyncPayload>(value: Object): SyncValidationResult<T> {
  if (!isObject(value)) { return { valid: false, error: '同步信封必须是对象' }; }
  const error: string = validateEnvelopeShape(value);
  if (error.length > 0) { return { valid: false, error: error }; }
  const envelope: SyncEnvelope<T> = clone(value as SyncEnvelope<T>);
  return { valid: true, envelope: envelope, error: '' };
}

export function createSyncEnvelope<T extends Object = SyncPayload>(snapshot: T, deviceId: string,
  revision: number, updatedAt: string = new Date().toISOString()): SyncEnvelope<T> {
  if (!isObject(snapshot)) { throw new Error('同步 snapshot 必须是对象'); }
  const envelope: SyncEnvelope<T> = {
    deviceId: deviceId,
    schemaVersion: SYNC_SCHEMA_VERSION,
    revision: revision,
    updatedAt: updatedAt,
    snapshotHash: computeSnapshotHash(snapshot),
    snapshot: clone(snapshot)
  };
  const checked: SyncValidationResult<T> = validateSyncEnvelope(envelope);
  if (!checked.valid || checked.envelope === undefined) { throw new Error(checked.error); }
  return checked.envelope;
}

export function serializeSyncEnvelope<T extends Object = SyncPayload>(envelope: SyncEnvelope<T>): string {
  const checked: SyncValidationResult<T> = validateSyncEnvelope(envelope);
  if (!checked.valid || checked.envelope === undefined) { throw new Error(checked.error); }
  return JSON.stringify(checked.envelope);
}

export function deserializeSyncEnvelope<T extends Object = SyncPayload>(payload: string): SyncEnvelope<T> {
  if (typeof payload !== 'string' || payload.length === 0) { throw new Error('同步信封序列化内容为空'); }
  let parsed: Object;
  try {
    parsed = JSON.parse(payload) as Object;
  } catch (error) {
    throw new Error('同步信封不是合法 JSON');
  }
  const checked: SyncValidationResult<T> = validateSyncEnvelope(parsed);
  if (!checked.valid || checked.envelope === undefined) { throw new Error(checked.error); }
  return checked.envelope;
}

export function exportSyncPackage<T extends Object = SyncPayload>(envelope: SyncEnvelope<T>,
  continuationPayload: string = '', exportedAt: string = new Date().toISOString()): string {
  const checked: SyncValidationResult<T> = validateSyncEnvelope(envelope);
  if (!checked.valid || checked.envelope === undefined) { throw new Error(checked.error); }
  if (!isValidTimestamp(exportedAt)) { throw new Error('同步包 exportedAt 不是有效时间'); }
  if (typeof continuationPayload !== 'string') { throw new Error('任务续接内容必须是字符串'); }
  const packageData: SyncPackage<T> = {
    format: SYNC_PACKAGE_FORMAT,
    packageVersion: SYNC_PACKAGE_VERSION,
    exportedAt: exportedAt,
    envelope: checked.envelope,
    continuationPayload: continuationPayload
  };
  return JSON.stringify(packageData);
}

export function importSyncPackage<T extends Object = SyncPayload>(payload: string): SyncPackage<T> {
  if (typeof payload !== 'string' || payload.length === 0) { throw new Error('同步包内容为空'); }
  let parsed: Object;
  try {
    parsed = JSON.parse(payload) as Object;
  } catch (error) {
    throw new Error('同步包不是合法 JSON');
  }
  if (!isObject(parsed)) { throw new Error('同步包必须是对象'); }
  const data: Record<string, Object> = parsed as Record<string, Object>;
  if (data.format !== SYNC_PACKAGE_FORMAT || data.packageVersion !== SYNC_PACKAGE_VERSION) {
    throw new Error('同步包格式或版本不支持');
  }
  if (!isValidTimestamp(data.exportedAt as string)) { throw new Error('同步包 exportedAt 无效'); }
  if (typeof data.continuationPayload !== 'string') { throw new Error('同步包缺少任务续接内容'); }
  const checked: SyncValidationResult<T> = validateSyncEnvelope(data.envelope);
  if (!checked.valid || checked.envelope === undefined) { throw new Error(checked.error); }
  return {
    format: SYNC_PACKAGE_FORMAT,
    packageVersion: SYNC_PACKAGE_VERSION,
    exportedAt: data.exportedAt as string,
    envelope: checked.envelope,
    continuationPayload: data.continuationPayload as string
  };
}

// 语义更直观的别名，方便 UI 层接“导出/导入同步包”按钮。
export const serializeSyncPackage = exportSyncPackage;
export const deserializeSyncPackage = importSyncPackage;

export class InMemoryLocalSyncTransport<T extends Object = SyncPayload> implements LocalSyncTransport<T> {
  private outgoing: SyncEnvelope<T>[] = [];
  private incoming: SyncEnvelope<T>[] = [];

  enqueue(envelope: SyncEnvelope<T>): SyncTransportReceipt {
    const checked: SyncValidationResult<T> = validateSyncEnvelope(envelope);
    if (!checked.valid || checked.envelope === undefined) {
      return { accepted: false, queued: false, online: false, messageId: '', message: checked.error };
    }
    const id: string = messageIdOf(checked.envelope);
    const duplicate: boolean = this.outgoing.some((item: SyncEnvelope<T>) => messageIdOf(item) === id);
    if (!duplicate) { this.outgoing.push(checked.envelope); }
    return { accepted: true, queued: true, online: false, messageId: id,
      message: duplicate ? '同步消息已在离线队列中' : '已加入离线同步队列，尚未发送' };
  }

  drain(): SyncEnvelope<T>[] {
    const result: SyncEnvelope<T>[] = this.incoming.slice();
    this.incoming = [];
    return result;
  }

  // 测试、分布式数据适配器和设备桥接层可用这些方法模拟另一端收到消息。
  pendingOutgoing(): SyncEnvelope<T>[] { return this.outgoing.map((item: SyncEnvelope<T>) => clone(item)); }
  takeOutgoing(): SyncEnvelope<T>[] {
    const result: SyncEnvelope<T>[] = this.pendingOutgoing();
    this.outgoing = [];
    return result;
  }
  injectIncoming(envelopes: SyncEnvelope<T>[]): void {
    for (const envelope of envelopes) { this.incoming.push(clone(envelope)); }
  }
  clear(): void { this.outgoing = []; this.incoming = []; }
}

// 没有传输能力时使用。它永远不会返回“已同步”，调用方可以据此保留重试入口。
export class NoopLocalSyncTransport<T extends Object = SyncPayload> implements LocalSyncTransport<T> {
  enqueue(envelope: SyncEnvelope<T>): SyncTransportReceipt {
    const checked: SyncValidationResult<T> = validateSyncEnvelope(envelope);
    return { accepted: false, queued: false, online: false,
      messageId: checked.valid ? messageIdOf(envelope) : '',
      message: checked.valid ? '当前没有可用同步传输，未发送' : checked.error };
  }

  drain(): SyncEnvelope<T>[] { return []; }
}

export class WardrobeSyncCoordinator<T extends Object = SyncPayload> implements SyncCoordinator<T> {
  private readonly deviceId: string;
  private readonly transport: LocalSyncTransport<T>;
  private local: SyncEnvelope<T>;
  private readonly receivedIds: string[] = [];
  private readonly pendingMessages: SyncEnvelope<T>[] = [];

  constructor(deviceId: string, initialSnapshot: T, initialRevision: number = 0,
    transport: LocalSyncTransport<T> = new InMemoryLocalSyncTransport<T>(),
    initialUpdatedAt: string = new Date().toISOString()) {
    this.deviceId = deviceId;
    this.transport = transport;
    this.local = createSyncEnvelope(initialSnapshot, deviceId, initialRevision, initialUpdatedAt);
  }

  createEnvelope(snapshot: T, revision: number, updatedAt?: string): SyncEnvelope<T> {
    return createSyncEnvelope(snapshot, this.deviceId, revision,
      updatedAt === undefined ? new Date().toISOString() : updatedAt);
  }

  async publish(snapshot: T, revision: number, updatedAt?: string): Promise<SyncTransportReceipt> {
    const envelope: SyncEnvelope<T> = this.createEnvelope(snapshot, revision, updatedAt);
    this.local = envelope;
    const receipt: SyncTransportReceipt = await this.transport.enqueue(envelope);
    if (receipt.queued && this.pendingMessages.every((item: SyncEnvelope<T>) =>
      messageIdOf(item) !== messageIdOf(envelope))) {
      this.pendingMessages.push(envelope);
    }
    return receipt;
  }

  merge(envelope: SyncEnvelope<T>): SyncMergeResult<T> {
    const checked: SyncValidationResult<T> = validateSyncEnvelope(envelope);
    if (!checked.valid || checked.envelope === undefined) {
      return { status: 'rejected', accepted: false, message: checked.error,
        snapshot: clone(this.local.snapshot), envelope: clone(this.local) };
    }
    const remote: SyncEnvelope<T> = checked.envelope;
    const id: string = messageIdOf(remote);
    if (this.receivedIds.indexOf(id) >= 0 || id === messageIdOf(this.local)) {
      return { status: 'duplicate', accepted: false, message: '重复同步消息，已忽略',
        snapshot: clone(this.local.snapshot), envelope: clone(this.local) };
    }

    const local: SyncEnvelope<T> = this.local;
    if (remote.revision > local.revision) {
      this.local = remote;
      this.receivedIds.push(id);
      return { status: 'applied', accepted: true, message: '远端 revision 更新，已采用远端快照',
        snapshot: clone(remote.snapshot), envelope: clone(remote) };
    }
    if (remote.revision < local.revision) {
      this.receivedIds.push(id);
      return { status: 'stale', accepted: false, message: '远端 revision 较旧，已保留本地快照',
        snapshot: clone(local.snapshot), envelope: clone(local) };
    }
    if (remote.snapshotHash === local.snapshotHash) {
      this.receivedIds.push(id);
      return { status: 'duplicate', accepted: false, message: 'revision 与快照均相同，已忽略重复消息',
        snapshot: clone(local.snapshot), envelope: clone(local) };
    }

    const localTime: number = new Date(local.updatedAt).getTime();
    const remoteTime: number = new Date(remote.updatedAt).getTime();
    let resolution: SyncConflictResolution = 'manual';
    let accepted: boolean = false;
    let message: string = 'revision 和 updatedAt 均相同但快照不同，需要人工处理';
    let resultEnvelope: SyncEnvelope<T> = local;
    if (remoteTime > localTime) {
      resolution = 'remote';
      accepted = true;
      message = 'revision 相同但远端 updatedAt 更新，按明确规则采用远端快照';
      this.local = remote;
      resultEnvelope = remote;
    } else if (remoteTime < localTime) {
      resolution = 'local';
      message = 'revision 相同但本地 updatedAt 更新，按明确规则保留本地快照';
    }
    this.receivedIds.push(id);
    const conflict: SyncConflict = {
      reason: message,
      localRevision: local.revision,
      remoteRevision: remote.revision,
      localUpdatedAt: local.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
      localHash: local.snapshotHash,
      remoteHash: remote.snapshotHash,
      resolution: resolution
    };
    return { status: 'conflict', accepted: accepted, message: message,
      snapshot: clone(resultEnvelope.snapshot), envelope: clone(resultEnvelope), conflict: conflict };
  }

  async receive(envelopes?: SyncEnvelope<T>[]): Promise<SyncMergeResult<T>[]> {
    const received: SyncEnvelope<T>[] = envelopes === undefined ? await this.transport.drain() : envelopes;
    const results: SyncMergeResult<T>[] = [];
    for (const envelope of received) { results.push(this.merge(envelope)); }
    return results;
  }

  currentEnvelope(): SyncEnvelope<T> { return clone(this.local); }

  pending(): SyncEnvelope<T>[] {
    return this.pendingMessages.map((item: SyncEnvelope<T>) => clone(item));
  }
}

export function createSyncCoordinator<T extends Object = SyncPayload>(deviceId: string, snapshot: T,
  revision: number = 0, transport?: LocalSyncTransport<T>): WardrobeSyncCoordinator<T> {
  return new WardrobeSyncCoordinator<T>(deviceId, snapshot, revision,
    transport === undefined ? new InMemoryLocalSyncTransport<T>() : transport);
}
