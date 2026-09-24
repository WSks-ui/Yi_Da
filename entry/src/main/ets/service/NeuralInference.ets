// 轻量推理服务的可替换契约。
//
// 当前仓库没有接入真实的 Neural Network Kit 模型文件，也不应为了演示凭空声称
// 已经运行了神经网络。因此离线演示只对调用方提供的实际数值特征做固定权重计算；
// URI 与图片尺寸不是像素特征，缺少数值特征时只返回低置信度空向量。将来接入模型时，实现
// NeuralInferenceProvider 并注入 NeuralInference 构造函数即可，调用方不需要改动。

export const INFERENCE_SOURCE_LOCAL: string = 'offline-heuristic';
export const INFERENCE_SOURCE_FALLBACK: string = 'offline-heuristic-fallback';
export const INFERENCE_SOURCE_UNAVAILABLE: string = 'unavailable';

export interface NeuralFeatureInput {
  // 固定顺序的已提取归一化特征；本地启发式不会从 URI 或尺寸字段伪造这些值。
  features?: number[];
  uri?: string;
  // 保留给真实 provider 解码图片时使用，本地占位计算不把它们当作视觉特征。
  width?: number;
  height?: number;
  channels?: number;
}

export type NeuralInferenceInput = number[] | string | NeuralFeatureInput;

export interface InferenceResult {
  // output 是固定顺序的归一化输出，便于后续 provider 使用同样的展示与排序契约。
  output: number[];
  // featureVector 保留推理实际使用的输入，演示页可以据此解释“离线特征”而不是伪造模型名。
  featureVector: number[];
  confidence: number;
  source: string;
  // status 用于把“有模型 provider 的真实输出”和“本地降级向量”明确区分开。
  status: string;
  method: string;
  modelAvailable: boolean;
  usedFallback: boolean;
  fallbackReason: string;
  labels: string[];
  // scores 是 output 的兼容别名，给未来的模型适配层一个更直观的字段名。
  scores: number[];
}

export interface NeuralInferenceProvider {
  inference(input: NeuralInferenceInput): Promise<InferenceResult>;
  // Provider 可以只声明能力，不必在未安装 Neural Network Kit 的设备上触发动态加载。
  isAvailable?(): boolean | Promise<boolean>;
  available?(): boolean | Promise<boolean>;
}

const OUTPUT_LABELS: string[] = ['亮度', '饱和度', '暖色倾向', '纹理强度', '轮廓明确度'];
const VECTOR_SIZE: number = 8;

function bounded(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) { return minimum; }
  return Math.max(minimum, Math.min(maximum, value));
}

function normalized(value: number): number {
  return Number(bounded(value, 0, 1).toFixed(4));
}

function vectorFromInput(input: NeuralInferenceInput): number[] {
  let raw: number[] = [];
  if (Array.isArray(input)) {
    raw = input.slice();
  } else if (typeof input !== 'string' && input.features && input.features.length > 0) {
    raw = input.features.slice();
  }

  const vector: number[] = [];
  for (let index: number = 0; index < VECTOR_SIZE; index++) {
    vector.push(normalized(index < raw.length ? raw[index] : 0));
  }
  return vector;
}

function isEmptyInput(input: NeuralInferenceInput): boolean {
  const features: number[] = Array.isArray(input) ? input
    : (typeof input === 'string' || input.features === undefined ? [] : input.features);
  return features.length === 0 || !features.some((value: number) => Number.isFinite(value));
}

function heuristicResult(input: NeuralInferenceInput, source: string, reason: string): InferenceResult {
  const featureVector: number[] = vectorFromInput(input);
  const hasFeatures: boolean = !isEmptyInput(input);
  const output: number[] = hasFeatures ? [
    normalized(featureVector[0] * 0.65 + featureVector[1] * 0.35),
    normalized(featureVector[2] * 0.7 + featureVector[3] * 0.3),
    normalized(featureVector[4] * 0.6 + (1 - featureVector[0]) * 0.4),
    normalized(featureVector[5] * 0.55 + featureVector[6] * 0.45),
    normalized(featureVector[7] * 0.7 + featureVector[2] * 0.3)
  ] : [0, 0, 0, 0, 0];
  let average: number = 0;
  for (const value of output) { average += value; }
  average /= output.length;
  // 空输入只返回低置信度向量，避免把默认零向量误认为有效图像特征。
  const confidence: number = hasFeatures ? Number((0.35 + average * 0.5).toFixed(2)) : 0.2;
  const scores: number[] = output.slice();
  return {
    output: output,
    featureVector: featureVector,
    confidence: bounded(confidence, 0, 1),
    source: source,
    status: 'unavailable',
    method: INFERENCE_SOURCE_LOCAL,
    modelAvailable: false,
    usedFallback: true,
    fallbackReason: reason,
    labels: OUTPUT_LABELS.slice(),
    scores: scores
  };
}

function normalizeProviderResult(result: InferenceResult): InferenceResult {
  const output: number[] = Array.isArray(result.output) ? result.output.slice() : [];
  const scores: number[] = output.slice();
  const vector: number[] = Array.isArray(result.featureVector) ? result.featureVector.slice() : [];
  return {
    output: output,
    featureVector: vector,
    confidence: bounded(result.confidence, 0, 1),
    source: result.source || 'neural-network-kit',
    status: 'available',
    method: result.source || 'neural-network-kit',
    modelAvailable: true,
    usedFallback: false,
    fallbackReason: '',
    labels: Array.isArray(result.labels) && result.labels.length > 0 ? result.labels.slice() : OUTPUT_LABELS.slice(),
    scores: scores
  };
}

async function providerAvailable(provider: NeuralInferenceProvider): Promise<boolean> {
  if (provider.isAvailable) {
    return await provider.isAvailable();
  }
  if (provider.available) {
    return await provider.available();
  }
  return true;
}

export class NeuralInference {
  private provider: NeuralInferenceProvider | undefined;

  constructor(provider?: NeuralInferenceProvider) {
    this.provider = provider;
  }

  setProvider(provider: NeuralInferenceProvider | undefined): void {
    this.provider = provider;
  }

  async inference(input: NeuralInferenceInput): Promise<InferenceResult> {
    if (this.provider === undefined) {
      return heuristicResult(input, INFERENCE_SOURCE_UNAVAILABLE,
        '未注入 Neural Network Kit provider；仅在收到实际数值特征时计算离线启发式');
    }
    try {
      if (!await providerAvailable(this.provider)) {
        return heuristicResult(input, INFERENCE_SOURCE_UNAVAILABLE,
          '模型 provider 不可用；仅在收到实际数值特征时计算离线启发式');
      }
      const result: InferenceResult = await this.provider.inference(input);
      return normalizeProviderResult(result);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '模型推理失败';
      return heuristicResult(input, INFERENCE_SOURCE_UNAVAILABLE,
        message || '模型推理失败；仅在收到实际数值特征时计算离线启发式');
    }
  }

  // 静态入口用于简单页面或脚本；实例入口用于注入真实 provider。
  static async inference(input: NeuralInferenceInput): Promise<InferenceResult> {
    return defaultNeuralInference.inference(input);
  }
}

// 该适配器刻意不导入具体 Kit：设备未安装共享包时，静态 import 可能导致应用启动失败。
// 集成真实模型时应在外层动态加载 Kit，再把完成了 inference 的对象注入 NeuralInference。
export class UnavailableNeuralInferenceProvider implements NeuralInferenceProvider {
  isAvailable(): boolean { return false; }

  async inference(input: NeuralInferenceInput): Promise<InferenceResult> {
    throw new Error('Neural Network Kit provider unavailable');
  }
}

const defaultNeuralInference: NeuralInference = new NeuralInference();

export async function inference(input: NeuralInferenceInput): Promise<InferenceResult> {
  return defaultNeuralInference.inference(input);
}

export function localHeuristicInference(input: NeuralInferenceInput): InferenceResult {
  return heuristicResult(input, INFERENCE_SOURCE_LOCAL,
    '本地启发式只处理实际数值特征；URI 或尺寸信息不作为视觉输入');
}
