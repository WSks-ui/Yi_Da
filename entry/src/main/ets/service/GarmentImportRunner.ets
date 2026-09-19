// 批量导入链：会话、串行拷贝、抠图、过期回调失效与清理。
//
// 为什么要单独一层：页面（Index）以前把这段逻辑写在组件方法里，业务检查没办法驱动它，
// 只能在测试里照抄一份"看起来一样"的状态机——那不是验证生产代码。
// 这里把平台操作作为接口注入（选择、导入、抠图、删除、存活判定），
// 状态转换仍然只走 service/GarmentImport.ets 的纯函数；
// 页面只负责把仓储与系统能力接进来，业务检查则注入测试替身，跑的是同一份实现。
//
// 关键约定：
//   - 拷贝严格串行：一项结束才开始下一项，不并发解码多张照片；
//   - 结果按任务 ID 写回，绝不写进"当前选中的项"；
//   - 失效结果（revision 已变 / 阶段已不在途 / 会话已结束）只做清理；
//   - 单项失败或跳过都不阻断剩余队列。
import { ImportFailureStep, ImportItem, ImportPhase } from '../model/GarmentImport';
import { beginCopy, beginCutout, beginSave, copyFailed, copySucceeded, createImportItem, cutoutFailed,
  cutoutSucceeded, dedupeUris, isActivePhase, makeGarmentId, makeSessionId, makeTaskId, markSkipped,
  nextPendingIndex, offsetFor, remainingCapacity, saveFailed, saveSucceeded, setUseCutout,
  writeBack } from './GarmentImport';

// 平台操作。页面注入真实实现，业务检查注入可控替身，跑的是同一条链。
export interface ImportHost {
  // 打开系统相册，返回所选 URI；取消时返回空数组。
  pick: (limit: number) => Promise<string[]>;
  // 把一张相册图片导入沙箱，返回本地 URI。失败必须 reject。
  copy: (sourceUri: string, taskId: string) => Promise<string>;
  // 主体抠图；不支持能力或失败都必须 reject 并给出可读原因。
  cutout: (originalUri: string, taskId: string) => Promise<string>;
  // 删除本应用拥有的临时文件；对不拥有的文件必须是空操作。
  discard: (uri: string) => Promise<void>;
  // 该图片是否仍被持久化记录引用（衣橱/日记/试穿）。被引用时清理必须跳过。
  isReferenced: (uri: string) => boolean;
  // 页面是否还接受写回；流程结束后返回 false，避免旧结果落进已放弃的会话。
  isAlive: () => boolean;
}

// 一次保存的结果：taskId 更新任务，garmentId 更新衣橱。
export interface SaveRequest {
  taskId: string;
  garmentId: string;
}

export class ImportSession {
  readonly sessionId: string;
  // 队列与当前项的唯一所有者就是这里；页面只持有它的快照。
  items: ImportItem[] = [];
  index: number = 0;
  // 唯一的状态发布通道：任何同步或异步改动都会调用它。
  private listener: (items: ImportItem[], index: number) => void = () => {};
  // 已启动过复制的任务 ID。串行推进据此挑选"下一个还没开始的任务"，
  // 而不是靠一个只增不减的下标：重试需要把某一项重新放回队列尾。
  private started: string[] = [];
  // 同一时刻只允许一项拷贝在途；这就是"处理一张、更新一张"的串行保证。
  private copyInFlight: boolean = false;
  private copyStarts: number = 0;
  private disposed: boolean = false;

  private constructor(sessionId: string) { this.sessionId = sessionId; }

  static create(now: number, salt: number): ImportSession {
    return new ImportSession(makeSessionId(now, salt));
  }

  // 注册唯一的发布通道。页面在这里接收新快照，不再自己维护第二份队列。
  subscribe(listener: (items: ImportItem[], index: number) => void): void {
    this.listener = listener;
    this.publish();
  }

  // 发布当前快照。
  private publish(): void { this.listener(this.items, this.index); }

  copyStartCount(): number { return this.copyStarts; }
  isCopying(): boolean { return this.copyInFlight; }
  isDisposed(): boolean { return this.disposed; }

  // 页面切换当前项：只动 index，不动任何草稿。
  select(index: number): void {
    if (this.disposed || index < 0 || index >= this.items.length || index === this.index) { return; }
    this.index = index;
    this.publish();
  }

  // 页面编辑字段：状态转换走纯函数，改完统一发布。
  edit(taskId: string, apply: (items: ImportItem[]) => ImportItem[]): void {
    if (this.disposed) { return; }
    const next: ImportItem[] = apply(this.items);
    if (next === this.items) { return; }
    this.items = next;
    this.publish();
  }

  // 设置是否使用抠图结果。
  useCutout(taskId: string, useCutout: boolean): void {
    const item: ImportItem | undefined = this.find(taskId);
    if (item === undefined || this.disposed || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED) { return; }
    const next: ImportItem[] = setUseCutout(this.items, taskId, useCutout);
    if (next !== this.items) { this.items = next; this.publish(); }
  }

  // 保存开始：任务进入 SAVING，重复提交会被挡住。
  beginSave(taskId: string): void {
    if (this.disposed) { return; }
    const next: ImportItem[] = beginSave(this.items, taskId);
    if (next !== this.items) { this.items = next; this.publish(); }
  }

  // 保存失败：回到 ERROR(SAVE)，草稿与图片都留着，可以原样重试。
  failSave(taskId: string, message: string): void {
    if (this.disposed) { return; }
    const next: ImportItem[] = saveFailed(this.items, taskId, message);
    if (next !== this.items) { this.items = next; this.publish(); }
  }

  // 标记某一项已保存。taskId 更新任务，garmentId 由调用方用于更新衣橱。
  // 先标记 SAVED，再允许退出清理：已保存项引用的图片会被 dispose 保护。
  markSaved(request: SaveRequest): void {
    if (this.disposed) { return; }
    const item: ImportItem | undefined = this.find(request.taskId);
    if (item === undefined || item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return; }
    // 兼容会话外部的直接确认调用，同时仍然让状态机经过 SAVING，避免终态被迟到回调复活。
    if (!isActivePhase(item.phase)) { this.items = beginSave(this.items, request.taskId); }
    this.items = saveSucceeded(this.items, request.taskId);
    const at: number = this.items.findIndex((item: ImportItem) => item.id === request.taskId);
    const next: number = nextPendingIndex(this.items, at);
    if (next >= 0) { this.index = next; }
    this.publish();
  }

  // 下一次拷贝应当在多少毫秒内没有新的拷贝启动（供检查串行性）。
  async pick(host: ImportHost, garmentCount: number): Promise<number> {
    if (this.disposed) { return 0; }
    const capacity: number = remainingCapacity(garmentCount);
    if (capacity <= 0) { return 0; }
    const uris: string[] = dedupeUris(await host.pick(capacity));
    if (this.disposed || !host.isAlive() || uris.length === 0) { return 0; }
    const offset: number = offsetFor(this.items, this.sessionId, uris.length);
    const created: ImportItem[] = uris.map((uri: string, i: number) =>
      createImportItem(makeTaskId(this.sessionId, offset + i),
        makeGarmentId(this.sessionId, offset + i), uri));
    this.items = this.items.concat(created);
    if (this.items.length === created.length) { this.index = 0; }
    for (const item of created) { this.items = beginCopy(this.items, item.id); }
    this.publish();
    this.pump(host);
    return created.length;
  }

  capacity(garmentCount: number): number { return remainingCapacity(garmentCount); }

  busy(): boolean { return this.items.some((item: ImportItem) => isActivePhase(item.phase)); }

  find(taskId: string): ImportItem | undefined {
    return this.items.find((item: ImportItem) => item.id === taskId);
  }

  // 只重试当前项失败的那一步，任务 ID 与衣物 ID 都不重建。
  // 复制与抠图都排进/走同一条串行通道，绝不与在途任务并发。
  retry(host: ImportHost, taskId: string): void {
    const item: ImportItem | undefined = this.find(taskId);
    if (item === undefined || this.disposed || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED) { return; }
    if (item.failureStep === ImportFailureStep.COPY) {
      this.items = beginCopy(this.items, taskId);
      // 重新放回串行队列：把它从"已启动"里移除，pump 才会再次取到它。
      this.started = this.started.filter((id: string) => id !== taskId);
      this.publish();
      // 正有拷贝在途时不必抢跑，等它结束后 pump 自然接管这一项。
      if (!this.copyInFlight) { this.pump(host); }
      return;
    }
    if (item.failureStep === ImportFailureStep.CUTOUT) { this.runCutout(host, taskId); }
  }

  // 抠图：不重复发起，也不在已有结果时重做。
  runCutout(host: ImportHost, taskId: string): void {
    const item: ImportItem | undefined = this.find(taskId);
    if (item === undefined || this.disposed || !host.isAlive() || isActivePhase(item.phase) ||
      item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return; }
    if (item.cutoutUri.length > 0 || item.originalUri.length === 0) { return; }
    // beginCutout 负责最终阶段判定。必须确认它确实进入 CUTTING，
    // 否则一次迟到的 UI 回调不能绕过状态机直接占用全局抠图能力。
    const next: ImportItem[] = beginCutout(this.items, taskId);
    const started: ImportItem | undefined = next.find((entry: ImportItem) => entry.id === taskId);
    if (next === this.items || started === undefined || started.phase !== ImportPhase.CUTTING) { return; }
    this.items = next;
    this.publish();
    const revision: number = started.revision;
    host.cutout(started.originalUri, taskId).then((uri: string) => {
      if (!writeBack(this.items, taskId, revision) || !host.isAlive() || this.disposed) {
        // 结果无处安放：只能清理，绝不重开页面或覆盖新项。
        this.discard(host, uri);
        return;
      }
      this.items = cutoutSucceeded(this.items, taskId, uri);
      this.publish();
    }).catch((error: Error) => {
      if (!writeBack(this.items, taskId, revision) || !host.isAlive() || this.disposed) { return; }
      this.items = cutoutFailed(this.items, taskId,
        (error as Error).message || '抠图失败，可重试或使用原图');
      this.publish();
    });
  }

  // 放弃一项：先让在途结果失效，再清理它拥有的文件，然后继续推进剩余队列。
  skip(host: ImportHost, taskId: string): void {
    const item: ImportItem | undefined = this.find(taskId);
    if (item === undefined || this.disposed || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED) { return; }
    const at: number = this.items.findIndex((entry: ImportItem) => entry.id === taskId);
    const doomed: string[] = [item.originalUri, item.cutoutUri];
    this.items = markSkipped(this.items, taskId);
    this.removeFiles(host, doomed);
    const next: number = nextPendingIndex(this.items, at);
    if (next >= 0) { this.index = next; }
    this.publish();
    this.pump(host);
  }

  // 结束会话：未保存项失效并清理，已保存项保留。
  dispose(host: ImportHost): void {
    if (this.disposed) { return; }
    const doomed: string[] = [];
    for (const item of this.items) {
      if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { continue; }
      doomed.push(item.originalUri, item.cutoutUri);
      this.items = markSkipped(this.items, item.id);
    }
    this.removeFiles(host, doomed);
    this.items = [];
    this.index = 0;
    this.started = [];
    this.disposed = true;
    this.publish();
  }

  // 保存成功后回收未被选用的那个版本；被持久化记录引用时跳过。
  releaseUnused(item: ImportItem, used: string, host: ImportHost): void {
    const unused: string = item.useCutout ? item.originalUri : item.cutoutUri;
    if (unused.length === 0 || unused === used) { return; }
    this.discard(host, unused);
  }

  // 串行泵：一次只启动一项拷贝，剩余任务等它结束后再推进。
  private pump(host: ImportHost): void {
    if (this.copyInFlight || this.disposed) { return; }
    for (const item of this.items) {
      if (item.phase !== ImportPhase.COPYING) { continue; }
      if (this.started.indexOf(item.id) >= 0) { continue; }
      this.started.push(item.id);
      this.startCopy(host, item);
      return;
    }
  }

  private startCopy(host: ImportHost, item: ImportItem): void {
    const revision: number = item.revision;
    this.copyInFlight = true;
    this.copyStarts++;
    host.copy(item.sourceUri, item.id).then((uri: string) => {
      this.copyInFlight = false;
      if (!writeBack(this.items, item.id, revision) || !host.isAlive() || this.disposed) {
        // 失效结果：文件归本任务所有；若已无人引用则回收。
        this.discard(host, uri);
        this.pump(host);
        return;
      }
      this.items = copySucceeded(this.items, item.id, uri);
      this.publish();
      this.pump(host);
    }).catch((error: Error) => {
      this.copyInFlight = false;
      if (writeBack(this.items, item.id, revision) && host.isAlive() && !this.disposed) {
        this.items = copyFailed(this.items, item.id,
          '导入失败：' + ((error as Error).message || '请重试或跳过'));
        this.publish();
      }
      // 单项失败同样继续推进剩余队列。
      this.pump(host);
    });
  }

  // 清理保护：只删本应用生成、当前任务拥有、且没有被持久化记录引用的文件。
  private discard(host: ImportHost, uri: string): void {
    if (uri.length === 0 || host.isReferenced(uri)) { return; }
    host.discard(uri).catch(() => {});
  }

  private removeFiles(host: ImportHost, uris: string[]): void {
    for (const uri of uris) { this.discard(host, uri); }
  }
}
