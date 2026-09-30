import { findDemoScene } from './TryOnDemo';

export enum TryOnStage {
  IDLE = 'idle', PREPARING = 'preparing', INTERACTING = 'interacting', PRESENTING = 'presenting',
  REVEALING = 'revealing', COMPLETE = 'complete'
}
export interface TryOnPresentation { stage: TryOnStage; sceneId: string; runId: number; }
export interface TryOnCommand { id: number; action: 'start' | 'compare'; sceneId: string; }
export interface PresentationScheduler {
  schedule: (callback: () => void, milliseconds: number) => number;
  clear: (id: number) => void;
}
export function presentationRunning(stage: TryOnStage): boolean {
  return stage !== TryOnStage.IDLE && stage !== TryOnStage.COMPLETE;
}
export function presentationText(stage: TryOnStage): string {
  if (stage === TryOnStage.PREPARING) { return '这次使用的是配套演示素材。'; }
  if (stage === TryOnStage.INTERACTING) { return '一起看看试穿效果的展示过程。'; }
  if (stage === TryOnStage.PRESENTING) { return '准备打开这组固定试穿样片。'; }
  if (stage === TryOnStage.REVEALING || stage === TryOnStage.COMPLETE) { return '样片已展示，可以查看原图对比。'; }
  return '选择一组配套素材，让搭搭带你体验。';
}

// 只管理演示时序，不拥有业务任务、不写快照，也不执行图像生成。
// 一个运行只保留一个计时器，cancel/dispose 立即清理；runId 同时拦截已经进入事件队列的旧回调。
// UI、提示和结果可见性必须订阅同一份状态，不得另外开启三个彼此不同步的计时器。
export class TryOnPresentationController {
  private current: TryOnPresentation = { stage: TryOnStage.IDLE, sceneId: '', runId: 0 };
  private listeners: ((state: TryOnPresentation) => void)[] = [];
  private timer: number = -1;
  private disposed: boolean = false;
  private scheduler: PresentationScheduler;

  constructor(scheduler?: PresentationScheduler) {
    this.scheduler = scheduler === undefined ? {
      schedule: (callback: () => void, milliseconds: number): number => setTimeout(callback, milliseconds),
      clear: (id: number): void => { clearTimeout(id); }
    } : scheduler;
  }
  snapshot(): TryOnPresentation {
    return { stage: this.current.stage, sceneId: this.current.sceneId, runId: this.current.runId };
  }
  subscribe(listener: (state: TryOnPresentation) => void): () => void {
    if (this.disposed) { return () => {}; }
    this.listeners.push(listener);
    listener(this.snapshot());
    return () => { this.listeners = this.listeners.filter((entry) => entry !== listener); };
  }
  start(sceneId: string): number {
    if (this.disposed) { throw new Error('演示已关闭'); }
    if (findDemoScene(sceneId) === undefined) { throw new Error('未知试穿样片场景'); }
    if (presentationRunning(this.current.stage)) { return this.current.runId; }
    this.clearTimer();
    this.current = { stage: TryOnStage.PREPARING, sceneId: sceneId, runId: this.current.runId + 1 };
    const runId: number = this.current.runId;
    this.publish();
    if (!this.disposed && this.current.runId === runId) { this.advance(runId, TryOnStage.INTERACTING, 1800); }
    return runId;
  }
  cancel(): void {
    if (this.disposed) { return; }
    this.clearTimer();
    this.current = { stage: TryOnStage.IDLE, sceneId: this.current.sceneId, runId: this.current.runId + 1 };
    this.publish();
  }
  dispose(): void {
    this.clearTimer();
    this.disposed = true;
    this.current = { stage: TryOnStage.IDLE, sceneId: this.current.sceneId, runId: this.current.runId + 1 };
    this.listeners = [];
  }
  private clearTimer(): void {
    if (this.timer >= 0) { this.scheduler.clear(this.timer); this.timer = -1; }
  }
  private publish(): void { for (const listener of this.listeners.slice()) { listener(this.snapshot()); } }
  private advance(runId: number, stage: TryOnStage, milliseconds: number): void {
    this.timer = this.scheduler.schedule(() => {
      if (this.disposed || runId !== this.current.runId) { return; }
      this.timer = -1;
      this.current = { stage: stage, sceneId: this.current.sceneId, runId: runId };
      this.publish();
      if (this.disposed || this.current.runId !== runId) { return; }
      if (stage === TryOnStage.INTERACTING) { this.advance(runId, TryOnStage.PRESENTING, 1800); }
      else if (stage === TryOnStage.PRESENTING) { this.advance(runId, TryOnStage.REVEALING, 1800); }
      else if (stage === TryOnStage.REVEALING) { this.advance(runId, TryOnStage.COMPLETE, 600); }
    }, milliseconds);
  }
}
