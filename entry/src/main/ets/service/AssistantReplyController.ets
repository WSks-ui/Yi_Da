// 回复的等待和逐字展示只属于界面呈现，不参与推荐计算、草稿编辑或业务快照提交。
// 关闭面板/进入后台会使本轮回调失效；历史消息保留完整文本，重新打开时不恢复旧动画。
export enum AssistantReplyStage { IDLE = 'idle', WAITING = 'waiting', TYPING = 'typing', COMPLETE = 'complete' }
export interface AssistantReplyView { messageId: string; text: string; stage: AssistantReplyStage; runId: number; }
export interface AssistantReplyScheduler {
  schedule(callback: () => void, delayMs: number): number;
  clear(timerId: number): void;
}
class ReplyTimer implements AssistantReplyScheduler {
  schedule(callback: () => void, delayMs: number): number { return setTimeout(callback, delayMs); }
  clear(timerId: number): void { clearTimeout(timerId); }
}
export function emptyAssistantReply(): AssistantReplyView {
  return { messageId: '', text: '', stage: AssistantReplyStage.IDLE, runId: 0 };
}
export function assistantReplyActive(view: AssistantReplyView): boolean {
  return view.stage === AssistantReplyStage.WAITING || view.stage === AssistantReplyStage.TYPING;
}
export class AssistantReplyController {
  private view: AssistantReplyView = emptyAssistantReply();
  private listeners: ((view: AssistantReplyView) => void)[] = [];
  private timerId: number = -1;
  private generation: number = 0;
  private disposed: boolean = false;
  private fullText: string = '';
  private cursor: number = 0;
  private scheduler: AssistantReplyScheduler;

  constructor(scheduler: AssistantReplyScheduler = new ReplyTimer()) { this.scheduler = scheduler; }
  snapshot(): AssistantReplyView {
    return { messageId: this.view.messageId, text: this.view.text, stage: this.view.stage, runId: this.view.runId };
  }
  subscribe(listener: (view: AssistantReplyView) => void): () => void {
    if (this.disposed) { return () => {}; }
    this.listeners.push(listener); listener(this.snapshot());
    return () => { this.listeners = this.listeners.filter((entry: (view: AssistantReplyView) => void) => entry !== listener); };
  }
  start(messageId: string, text: string): void {
    if (this.disposed || messageId.length === 0 || text.length === 0) { return; }
    this.clearTimer(); const runId: number = ++this.generation;
    this.fullText = text; this.cursor = 0;
    this.view = { messageId: messageId, text: '', stage: AssistantReplyStage.WAITING, runId: runId };
    this.publish();
    if (this.valid(runId)) { this.schedule(runId, 1000); }
  }
  cancel(): void {
    this.clearTimer(); this.generation++; this.fullText = ''; this.cursor = 0;
    this.view = emptyAssistantReply(); this.publish();
  }
  dispose(): void { this.disposed = true; this.cancel(); this.listeners = []; }
  private clearTimer(): void {
    if (this.timerId >= 0) { this.scheduler.clear(this.timerId); this.timerId = -1; }
  }
  private valid(runId: number): boolean { return !this.disposed && runId === this.generation; }
  private publish(): void {
    for (const listener of this.listeners.slice()) { listener(this.snapshot()); }
  }
  private schedule(runId: number, delayMs: number): void {
    this.timerId = this.scheduler.schedule(() => {
      if (!this.valid(runId)) { return; }
      this.timerId = -1;
      // 长回复每帧展示一小组字符，逐字过程控制在约 2.5 秒内；不切断 emoji 的 UTF-16 代理对。
      const step: number = Math.max(1, Math.ceil(this.fullText.length / 90));
      let next: number = Math.min(this.fullText.length, this.cursor + step);
      const last: number = this.fullText.charCodeAt(next - 1);
      if (next < this.fullText.length && last >= 0xD800 && last <= 0xDBFF) { next++; }
      this.cursor = next;
      this.view = { messageId: this.view.messageId, text: this.fullText.slice(0, next), runId: runId,
        stage: next === this.fullText.length ? AssistantReplyStage.COMPLETE : AssistantReplyStage.TYPING };
      this.publish();
      if (this.valid(runId) && this.view.stage === AssistantReplyStage.TYPING) { this.schedule(runId, 26); }
    }, delayMs);
  }
}
