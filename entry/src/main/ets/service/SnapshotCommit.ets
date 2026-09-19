// 快照提交锁。
//
// 为什么需要它：仓储自己的写队列只能保证"两次磁盘写不交叉"，不能保证"后写的快照更新"——
// 调用方各自构造全量快照时，先构造的那份可能后落盘，把新数据整段盖回去。
//
// 顺序契约（任务 A 验收项 A11 直接检查这条）：
//   1. 先让候选快照落盘成功；
//   2. 落盘成功后**才**发布新的业务状态（调用方在 commit 成功返回后再改内存）；
//   3. 最后才处理延后的天气、补存与导航。
// 失败路径只登记 notice，绝不发布成功、绝不应用延后项。
//
// 锁只覆盖一次实际磁盘提交，不覆盖用户填表单的时间。
//
// 这个类是纯状态机，平台调用（repository.save）由调用方注入，
// 因此 Node 侧的业务检查可以直接驱动**真实实现**，不需要在测试里复制一份。
export interface CommitCallbacks {
  // 一次实际磁盘提交。必须真实落盘后才 resolve。
  save: (snapshot: string) => Promise<void>;
  // 落盘成功后发布业务状态（把候选状态并入内存）。抛错视为发布失败，走失败路径。
  publish: () => void;
  // 发布之后处理延后项：应用待处理的天气、按需补存、执行被推迟的导航。
  afterPublish: () => void;
  // 失败路径：只提示，不发布。
  onFailure: (reason: string) => void;
  // 业务请求撞上已有提交时的专用回调。它与保存失败分开，避免把未执行的请求登记成可重试候选。
  onBusy?: () => void;
}

// 只有 RESAVE 可以在锁内登记补存；业务提交在锁内必须明确失败，不能伪造成功。
export enum CommitKind {
  BUSINESS = 'business',
  RESAVE = 'resave'
}

export class SnapshotCommit {
  private locked: boolean = false;
  private resaveNeeded: boolean = false;
  // 锁期间到达的外部变更（例如天气结果），延后到发布之后再应用。
  // 用 NaN 表示"没有待处理温度"：ArkTS 不允许把 undefined 赋给 number 字段。
  private pendingTemperature: number = Number.NaN;
  private cardOpenPending: boolean = false;

  private constructor() {}

  static create(): SnapshotCommit { return new SnapshotCommit(); }

  isLocked(): boolean { return this.locked; }
  needsResave(): boolean { return this.resaveNeeded; }
  hasPendingTemperature(): boolean { return !Number.isNaN(this.pendingTemperature); }
  isCardOpenPending(): boolean { return this.cardOpenPending; }

  // 提交进行中时，外部变更只登记、不立即生效。
  deferTemperature(mid: number): void { this.pendingTemperature = mid; }
  deferCardOpen(): void { this.cardOpenPending = true; }

  // 取走并清空待处理温度；返回 NaN 表示没有。
  takeTemperature(): number {
    const mid: number = this.pendingTemperature;
    this.pendingTemperature = Number.NaN;
    return mid;
  }

  takeCardOpen(): boolean {
    const pending: boolean = this.cardOpenPending;
    this.cardOpenPending = false;
    return pending;
  }

  requestResave(): void { this.resaveNeeded = true; }

  // 取走并清空"需要补存"标记；返回 true 表示调用方应当用最新状态补存一次。
  takeResave(): boolean {
    const needed: boolean = this.resaveNeeded;
    this.resaveNeeded = false;
    return needed;
  }

  // 一次提交。返回 true 只代表"落盘并发布都完成"。
  // 业务请求与内部补存必须明确区分：锁内业务请求不进入补存队列，也绝不返回成功。
  async commit(snapshot: string, callbacks: CommitCallbacks,
    kind: CommitKind = CommitKind.BUSINESS): Promise<boolean> {
    if (this.locked) {
      if (kind === CommitKind.RESAVE) { this.resaveNeeded = true; }
      if (callbacks.onBusy !== undefined && kind === CommitKind.BUSINESS) {
        callbacks.onBusy();
      }
      return false;
    }
    this.locked = true;
    let committed: boolean = false;
    try {
      await callbacks.save(snapshot);
      // publish 也属于提交的一部分。发布抛错时不能执行 afterPublish，也不能报告成功。
      callbacks.publish();
      committed = true;
    } catch (error) {
      callbacks.onFailure((error as Error).message || '保存失败');
    } finally {
      this.locked = false;
    }
    if (committed) { callbacks.afterPublish(); }
    return committed;
  }
}
