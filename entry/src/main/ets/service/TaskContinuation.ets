// 试穿、导入以及其他异步任务的离线续接队列。
//
// 队列只管理可序列化的状态，不打开文件、不拼接应用私有目录，也不启动网络请求。
// 调用方负责把 serialize() 的结果交给自己的存储适配器，并在重新进入应用后调用
// restore()；这样同一套状态机可以用于手机、平板和后续的分布式数据实现。

export const CONTINUATION_SCHEMA_VERSION: number = 1;

export type ContinuationTaskKind = 'try-on' | 'import' | 'task';
export type ContinuationStatus = 'pending' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';

export type ContinuationTaskPayload = Record<string, Object>;

export interface ContinuationTask {
  // taskId 是跨设备幂等键；id 作为兼容别名一并保存，避免不同调用方各自生成第二个任务。
  taskId: string;
  id: string;
  kind: ContinuationTaskKind;
  status: ContinuationStatus;
  payload: ContinuationTaskPayload;
  progress: number;
  createdAt: string;
  updatedAt: string;
  message: string;
  error: string;
  cancelReason: string;
}

export interface ContinuationTaskInput {
  taskId: string;
  kind: ContinuationTaskKind;
  payload?: ContinuationTaskPayload;
  createdAt?: string;
}

export interface ContinuationOperationResult {
  changed: boolean;
  message: string;
  task?: ContinuationTask;
}

// 持久化由调用方注入。实现可以是 Preferences、分布式数据或测试内存，队列不感知路径。
export interface ContinuationStore {
  read(): Promise<string> | string;
  write(payload: string): Promise<void> | void;
}

export interface ContinuationQueue {
  enqueue(input: ContinuationTaskInput): ContinuationOperationResult;
  pause(taskId: string, reason?: string): ContinuationOperationResult;
  resume(taskId: string): ContinuationOperationResult;
  cancel(taskId: string, reason?: string): ContinuationOperationResult;
  update(taskId: string, progress: number, message?: string): ContinuationOperationResult;
  complete(taskId: string, message?: string): ContinuationOperationResult;
  fail(taskId: string, error: string): ContinuationOperationResult;
  get(taskId: string): ContinuationTask | undefined;
  list(): ContinuationTask[];
  serialize(): string;
  restore(serialized: string): number;
}

const TASK_KINDS: ContinuationTaskKind[] = ['try-on', 'import', 'task'];
const TASK_STATUSES: ContinuationStatus[] = ['pending', 'running', 'paused', 'completed', 'failed', 'cancelled'];

function isObject(value: Object | null | undefined): boolean {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value);
}

function clone<T extends Object>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function isValidTime(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(new Date(value).getTime());
}

function copyPayload(value: ContinuationTaskPayload | undefined): ContinuationTaskPayload {
  if (value === undefined) { return {}; }
  if (!isObject(value)) { throw new Error('任务 payload 必须是对象'); }
  return clone(value);
}

function stableValue(value: Object | null | undefined): string {
  if (value === null) { return 'null'; }
  if (value === undefined) { return 'undefined'; }
  if (typeof value === 'string') { return JSON.stringify(value); }
  if (typeof value === 'number' || typeof value === 'boolean') { return String(value); }
  if (Array.isArray(value)) { return '[' + value.map((item: Object) => stableValue(item)).join(',') + ']'; }
  const record: Record<string, Object> = value as Record<string, Object>;
  const keys: string[] = Object.keys(record).sort();
  return '{' + keys.map((key: string) => JSON.stringify(key) + ':' + stableValue(record[key])).join(',') + '}';
}

function samePayload(left: ContinuationTaskPayload, right: ContinuationTaskPayload): boolean {
  return stableValue(left) === stableValue(right);
}

function isTerminal(status: ContinuationStatus): boolean {
  return status === 'completed' || status === 'cancelled';
}

function operation(task: ContinuationTask | undefined, changed: boolean, message: string): ContinuationOperationResult {
  return { changed: changed, message: message, task: task === undefined ? undefined : clone(task) };
}

function validateTask(value: Object): string {
  if (!isObject(value)) { return '任务项必须是对象'; }
  const item: Record<string, Object> = value as Record<string, Object>;
  if (typeof item.taskId !== 'string' || item.taskId.length === 0) { return '任务缺少 taskId'; }
  if (typeof item.id !== 'string' || item.id !== item.taskId) { return '任务 id 与 taskId 不一致'; }
  if (TASK_KINDS.indexOf(item.kind as ContinuationTaskKind) < 0) { return '任务类型不支持'; }
  if (TASK_STATUSES.indexOf(item.status as ContinuationStatus) < 0) { return '任务状态不支持'; }
  if (!isObject(item.payload)) { return '任务 payload 必须是对象'; }
  if (typeof item.progress !== 'number' || !Number.isFinite(item.progress) || item.progress < 0 || item.progress > 1) {
    return '任务 progress 必须在 0 到 1 之间';
  }
  if (!isValidTime(item.createdAt as string) || !isValidTime(item.updatedAt as string)) {
    return '任务时间字段无效';
  }
  if (typeof item.message !== 'string' || typeof item.error !== 'string' || typeof item.cancelReason !== 'string') {
    return '任务文本字段无效';
  }
  return '';
}

function normalizeNow(value: string | undefined): string {
  const result: string = value === undefined ? new Date().toISOString() : value;
  if (!isValidTime(result)) { throw new Error('任务时间无效'); }
  return result;
}

export class TaskContinuationQueue implements ContinuationQueue {
  private tasks: ContinuationTask[] = [];

  // 入队是幂等操作：同一 taskId 且内容相同直接返回原任务，禁止重复创建。
  enqueue(input: ContinuationTaskInput): ContinuationOperationResult {
    if (!input || typeof input.taskId !== 'string' || input.taskId.length === 0) {
      throw new Error('任务 taskId 不能为空');
    }
    if (TASK_KINDS.indexOf(input.kind) < 0) { throw new Error('任务类型不支持'); }
    const payload: ContinuationTaskPayload = copyPayload(input.payload);
    const now: string = normalizeNow(input.createdAt);
    const existing: ContinuationTask | undefined = this.get(input.taskId);
    if (existing !== undefined) {
      if (existing.kind !== input.kind || !samePayload(existing.payload, payload)) {
        throw new Error('相同 taskId 已绑定其他任务内容');
      }
      return operation(existing, false, '任务已存在，保持幂等');
    }
    const task: ContinuationTask = {
      taskId: input.taskId,
      id: input.taskId,
      kind: input.kind,
      status: 'pending',
      payload: payload,
      progress: 0,
      createdAt: now,
      updatedAt: now,
      message: '',
      error: '',
      cancelReason: ''
    };
    this.tasks.push(task);
    return operation(task, true, '任务已加入续接队列');
  }

  // 便于页面按常见参数直接创建任务；核心仍然通过 enqueue 统一保证幂等。
  createTask(taskId: string, kind: ContinuationTaskKind, payload: ContinuationTaskPayload = {},
    createdAt?: string): ContinuationOperationResult {
    return this.enqueue({ taskId: taskId, kind: kind, payload: payload, createdAt: createdAt });
  }

  start(taskId: string): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (task.status === 'pending') {
      task.status = 'running';
      task.updatedAt = normalizeNow(undefined);
      return operation(task, true, '任务已恢复执行');
    }
    if (task.status === 'running') { return operation(task, false, '任务已经在执行'); }
    return operation(task, false, '当前任务状态不能开始');
  }

  pause(taskId: string, reason: string = '用户暂停'): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (task.status === 'paused') { return operation(task, false, '任务已经暂停'); }
    if (isTerminal(task.status)) { return operation(task, false, '终态任务不能暂停'); }
    task.status = 'paused';
    task.message = reason;
    task.updatedAt = normalizeNow(undefined);
    return operation(task, true, '任务已暂停，可稍后恢复');
  }

  resume(taskId: string): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (task.status === 'paused' || task.status === 'pending') {
      task.status = 'running';
      task.updatedAt = normalizeNow(undefined);
      return operation(task, true, '任务已恢复');
    }
    if (task.status === 'running') { return operation(task, false, '任务已经在执行'); }
    return operation(task, false, '终态任务不能恢复');
  }

  cancel(taskId: string, reason: string = '用户取消'): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (task.status === 'cancelled') { return operation(task, false, '任务已经取消'); }
    if (task.status === 'completed') { return operation(task, false, '已完成任务不能取消'); }
    task.status = 'cancelled';
    task.cancelReason = reason;
    task.updatedAt = normalizeNow(undefined);
    return operation(task, true, '任务已取消');
  }

  update(taskId: string, progress: number, message: string = ''): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (isTerminal(task.status)) { return operation(task, false, '终态任务不能更新进度'); }
    if (!Number.isFinite(progress) || progress < 0 || progress > 1) { throw new Error('任务 progress 必须在 0 到 1 之间'); }
    task.progress = progress;
    task.message = message;
    task.updatedAt = normalizeNow(undefined);
    return operation(task, true, '任务进度已更新');
  }

  complete(taskId: string, message: string = '任务完成'): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (task.status === 'completed') { return operation(task, false, '任务已经完成'); }
    if (task.status === 'cancelled') { return operation(task, false, '已取消任务不能完成'); }
    task.status = 'completed';
    task.progress = 1;
    task.message = message;
    task.error = '';
    task.updatedAt = normalizeNow(undefined);
    return operation(task, true, '任务已完成');
  }

  fail(taskId: string, error: string): ContinuationOperationResult {
    const task: ContinuationTask | undefined = this.findMutable(taskId);
    if (task === undefined) { return operation(undefined, false, '任务不存在'); }
    if (isTerminal(task.status)) { return operation(task, false, '终态任务不能标记失败'); }
    task.status = 'failed';
    task.error = error;
    task.updatedAt = normalizeNow(undefined);
    return operation(task, true, '任务已记录失败，可由调用方重新入队');
  }

  get(taskId: string): ContinuationTask | undefined {
    const found: ContinuationTask | undefined = this.tasks.find((item: ContinuationTask) => item.taskId === taskId);
    return found === undefined ? undefined : clone(found);
  }

  list(): ContinuationTask[] { return this.tasks.map((item: ContinuationTask) => clone(item)); }

  serialize(): string {
    return JSON.stringify({ schemaVersion: CONTINUATION_SCHEMA_VERSION, tasks: this.tasks });
  }

  restore(serialized: string): number {
    let parsed: Object;
    try {
      parsed = JSON.parse(serialized) as Object;
    } catch (error) {
      throw new Error('任务续接数据不是合法 JSON');
    }
    if (!isObject(parsed)) { throw new Error('任务续接数据必须是对象'); }
    const root: Record<string, Object> = parsed as Record<string, Object>;
    if (root.schemaVersion !== CONTINUATION_SCHEMA_VERSION || !Array.isArray(root.tasks)) {
      throw new Error('任务续接 schemaVersion 或 tasks 无效');
    }
    const restored: ContinuationTask[] = [];
    for (const value of root.tasks as Object[]) {
      const error: string = validateTask(value);
      if (error.length > 0) { throw new Error('任务续接数据无效：' + error); }
      const task: ContinuationTask = clone(value as ContinuationTask);
      if (restored.some((item: ContinuationTask) => item.taskId === task.taskId)) {
        throw new Error('任务续接数据包含重复 taskId');
      }
      restored.push(task);
    }
    this.tasks = restored;
    return restored.length;
  }

  async persist(store: ContinuationStore): Promise<void> {
    await store.write(this.serialize());
  }

  async restoreFrom(store: ContinuationStore): Promise<number> {
    return this.restore(await store.read());
  }

  private findMutable(taskId: string): ContinuationTask | undefined {
    return this.tasks.find((item: ContinuationTask) => item.taskId === taskId);
  }
}

export function deserializeContinuationQueue(serialized: string): TaskContinuationQueue {
  const queue: TaskContinuationQueue = new TaskContinuationQueue();
  queue.restore(serialized);
  return queue;
}
