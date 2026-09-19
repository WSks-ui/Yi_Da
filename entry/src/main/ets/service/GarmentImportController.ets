// 批量录入的会话接线：把页面中的队列操作、串行任务和退出清理集中到一个可检查的类。
//
// Index 负责全局 SnapshotCommit、候选快照、提交锁和失败重试；本控制器只管理
// ImportSession 的生命周期、状态发布以及导入文件的会话级清理，避免把两套提交协调逻辑混在一起。
import { ImportFailureStep, ImportItem, ImportPhase } from '../model/GarmentImport';
import { nextDraftFileKey } from './GarmentImport';
import { ImportHost, ImportSession } from './GarmentImportRunner';

export class GarmentImportController {
  private session: ImportSession | undefined = undefined;
  private draftSeqSession: string = '';
  private readonly host: ImportHost;

  // Controller 只拥有导入会话；快照提交由 Index 的全局 SnapshotCommit 统一协调。
  constructor(host: ImportHost) { this.host = host; }

  // ---- 唯一状态所有者：ImportSession ----

  sessionRef(now: number, salt: number,
    onChange: (items: ImportItem[], index: number) => void): ImportSession {
    if (this.session === undefined) {
      const created: ImportSession = ImportSession.create(now, salt);
      // 会话是唯一发布通道：页面在这里接收快照，不再维护第二份队列。
      created.subscribe(onChange);
      this.session = created;
    }
    return this.session as ImportSession;
  }

  currentSession(): ImportSession | undefined { return this.session; }
  items(): ImportItem[] { return this.session !== undefined ? this.session.items : []; }
  index(): number { return this.session !== undefined ? this.session.index : 0; }

  // ---- 编辑与切项：全部经会话 ----

  select(index: number): void { if (this.session !== undefined) { this.session.select(index); } }
  edit(taskId: string, apply: (items: ImportItem[]) => ImportItem[]): void {
    if (this.session !== undefined) { this.session.edit(taskId, apply); }
  }
  useCutout(taskId: string, value: boolean): void {
    if (this.session !== undefined) { this.session.useCutout(taskId, value); }
  }
  skip(taskId: string): void {
    if (this.session !== undefined) { this.session.skip(this.host, taskId); }
  }
  cutout(taskId: string): void {
    if (this.session !== undefined) { this.session.runCutout(this.host, taskId); }
  }

  // 重试严格按 failureStep 分派；COPY 回到串行队列，由会话保证不与在途复制并发。
  retry(taskId: string, savePhase: (taskId: string) => void): void {
    const session: ImportSession | undefined = this.session;
    if (session === undefined) { return; }
    const item: ImportItem | undefined = session.find(taskId);
    if (item === undefined) { return; }
    if (item.failureStep === ImportFailureStep.SAVE) { savePhase(taskId); return; }
    session.retry(this.host, taskId);
  }

  // ---- 单件换图的文件标识 ----

  nextDraftKey(sessionId: string): string {
    if (this.draftSeqSession !== sessionId) { this.draftSeqSession = sessionId; }
    return nextDraftFileKey(sessionId);
  }

  // ---- 退出：未保存项失效清理，已保存项与其引用的图片保留 ----

  exit(): number {
    const session: ImportSession | undefined = this.session;
    if (session === undefined) { return 0; }
    let saved: number = 0;
    for (const item of session.items) {
      if (item.phase === ImportPhase.SAVED) { saved++; }
    }
    session.dispose(this.host);
    this.session = undefined;
    return saved;
  }

  isDisposed(): boolean { return this.session === undefined; }
}
