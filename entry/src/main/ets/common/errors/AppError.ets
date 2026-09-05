export class AppError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'AppError';
    this.code = code;
  }
}

export function errorMessage(error: Error): string {
  if (error instanceof AppError) { return error.message; }
  const code = Number((error as AppError).code);
  if (code === 201 || code === 13900001 || code === 13900012 || code === 14800023) {
    return '没有访问所需数据或照片的权限，请重新授权或重新选择照片。';
  }
  if (code === 13900002) { return '照片已移动或删除，请重新选择；已保存的衣物属性不会被删除。'; }
  if (code === 13900025 || code === 14800029) { return '存储空间不足，请释放空间后重试；原有衣物保持不变。'; }
  // 不将平台异常的 URI、SQL、文件名或上下文直接展示/写入普通日志。
  return '操作未完成，请检查可用存储空间后重试；原有衣物不会被清空。';
}
