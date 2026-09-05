import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { AppError } from '../../common/errors/AppError';

export class AppDatabase {
  private store?: relationalStore.RdbStore;
  private opening?: Promise<void>;
  private queue: Promise<void> = Promise.resolve();
  private context: common.Context;
  private name: string;

  constructor(context: common.Context, name: string = 'yida.db') {
    this.context = context;
    this.name = name;
  }

  async open(): Promise<void> {
    if (this.store) { return; }
    if (!this.opening) { this.opening = this.initialize(); }
    try {
      await this.opening;
    } finally {
      this.opening = undefined;
    }
  }

  private async initialize(): Promise<void> {
    const store = await relationalStore.getRdbStore(this.context, {
      name: this.name, securityLevel: relationalStore.SecurityLevel.S3, allowRebuild: false
    });
    try {
      await store.executeSql('PRAGMA foreign_keys = ON');
      // querySql 可能命中只读连接，不能用它验证写连接的 PRAGMA。
      // API 26 模拟器实测存在该差异；execute 在写连接读取标量，再用非法引用测试验证。
      if (await store.execute('PRAGMA foreign_keys') !== 1) {
        throw new AppError('FOREIGN_KEYS_DISABLED', '数据库外键未启用，已停止写入。');
      }
      if (store.version > 1) {
        throw new AppError('NEWER_DATABASE', '本地数据由较新版本创建，请更新应用；不会清空数据。');
      }
      if (store.version === 0) {
        const bytes = await this.context.resourceManager.getRawFileContent('database/v1.json');
        const statements = JSON.parse(new util.TextDecoder().decodeToString(bytes)) as string[];
        store.beginTransaction();
        try {
          for (const statement of statements) { await store.execute(statement); }
          store.commit();
        } catch (error) {
          store.rollBack();
          throw error as Error;
        }
      }
      const violations = await store.querySql('PRAGMA foreign_key_check');
      try {
        if (violations.rowCount > 0) { throw new AppError('DATABASE_INTEGRITY', '数据库引用检查失败，已保留原数据。'); }
      } finally { violations.close(); }
      this.store = store;
    } catch (error) {
      await store.close();
      throw error as Error;
    }
  }

  run<T>(work: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    // 同一连接的读取、写入和清理按顺序执行；失败不能毒化后续队列。
    const result = this.queue.then(async (): Promise<T> => {
      await this.open();
      return work(this.store!);
    });
    this.queue = result.then(() => {}, () => {});
    return result;
  }

  transaction<T>(work: (transaction: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    return this.run(async (store: relationalStore.RdbStore): Promise<T> => {
      // 使用同一写连接的事务，避免 createTransaction 新连接未继承 foreign_keys。
      // 事务期间所有访问经过上方队列，禁止嵌套调用 run/transaction 导致自等待。
      store.beginTransaction();
      try {
        const result = await work(store);
        store.commit();
        return result;
      } catch (error) {
        store.rollBack();
        throw error as Error;
      }
    });
  }

  async close(): Promise<void> {
    await this.queue;
    if (this.store) { await this.store.close(); }
    this.store = undefined;
  }
}
