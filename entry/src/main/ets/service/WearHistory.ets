import { DiaryEntry, WearRecord, Garment, copyGarment } from '../model/Wardrobe';

// 使用本地日历日期，避免 UTC 转换把凌晨的穿搭记到前一天。
export function localDay(date: Date = new Date()): string {
  return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' +
    String(date.getDate()).padStart(2, '0');
}

// 旧版中文设备用斜线或点分隔日期。只接受明确的年/月/日，不猜测月/日/年的地区格式。
export function normalizedDay(value: string): string {
  const match: RegExpMatchArray | null = value.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (match === null) { return value; }
  const date: Date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  if (date.getFullYear() !== Number(match[1]) || date.getMonth() + 1 !== Number(match[2]) ||
    date.getDate() !== Number(match[3])) { return value; }
  return localDay(date);
}

export function recordedDays(diary: DiaryEntry[], records: WearRecord[]): string[] {
  const days: string[] = [];
  for (const entry of diary) {
    const key: string = normalizedDay(entry.date);
    if (days.indexOf(key) < 0) { days.push(key); }
  }
  for (const record of records) {
    const key: string = normalizedDay(record.date);
    if (days.indexOf(key) < 0) { days.push(key); }
  }
  return days;
}

// 新版反馈同时生成日记。相同日期与衣物的重复提交不受数组顺序或旧日期格式影响。
export function hasWear(records: WearRecord[], date: string, garmentIds: string[]): boolean {
  const signature: string = garmentIds.slice().sort().join(',');
  return records.some((record: WearRecord) => normalizedDay(record.date) === normalizedDay(date) &&
    record.garmentIds.slice().sort().join(',') === signature);
}

export interface DiaryMutation {
  diary: DiaryEntry[];
  records: WearRecord[];
  garments: Garment[];
  error: string;
}

function relatedRecord(entry: DiaryEntry, record: WearRecord): boolean {
  return entry.id === 'wear_' + record.id || entry.id === record.id;
}

function wasCounted(entry: DiaryEntry, records: WearRecord[]): boolean {
  return entry.wearCounted === true || records.some((record: WearRecord) => relatedRecord(entry, record));
}

function adjustCounts(garments: Garment[], previous: string[], next: string[]): Garment[] {
  return garments.map((item: Garment) => {
    const updated: Garment = copyGarment(item);
    updated.wearCount = Math.max(0, item.wearCount - (previous.indexOf(item.id) >= 0 ? 1 : 0) +
      (next.indexOf(item.id) >= 0 ? 1 : 0));
    return updated;
  });
}

// 两个入口共用这条变更路径。同日、同组合只计一次；编辑先撤销旧组合再记新组合。
// counted 标记保存在日记中，因此旧穿着记录超过保留上限时，删除日记仍能准确撤销次数。
export function saveDiary(diary: DiaryEntry[], records: WearRecord[], garments: Garment[], entry: DiaryEntry): DiaryMutation {
  const unchanged: DiaryMutation = { diary: diary, records: records, garments: garments, error: '' };
  const ids: string[] = entry.garmentIds.filter((id: string, index: number) => entry.garmentIds.indexOf(id) === index);
  if (ids.length === 0 || ids.some((id: string) => !garments.some((item: Garment) => item.id === id))) {
    unchanged.error = '请至少选择一件仍在衣橱中的衣物'; return unchanged;
  }
  const signature: string = ids.slice().sort().join(',');
  const date: string = normalizedDay(entry.date);
  const duplicate: boolean = diary.some((item: DiaryEntry) => item.id !== entry.id &&
    normalizedDay(item.date) === date && item.garmentIds.slice().sort().join(',') === signature) ||
    records.some((record: WearRecord) => !relatedRecord(entry, record) && normalizedDay(record.date) === date &&
      record.garmentIds.slice().sort().join(',') === signature);
  if (duplicate) { unchanged.error = '这一天已经记录过这套穿搭'; return unchanged; }
  const old: DiaryEntry | undefined = diary.find((item: DiaryEntry) => item.id === entry.id);
  if (!old && diary.length >= 200) { unchanged.error = '日记已满，请先整理历史记录'; return unchanged; }
  const saved: DiaryEntry = { id: entry.id, date: date, garmentIds: ids, note: entry.note,
    photoUri: entry.photoUri, weather: entry.weather, temperature: entry.temperature,
    occasion: entry.occasion, feedback: entry.feedback, wearCounted: true };
  const recordId: string = entry.id.startsWith('wear_') ? entry.id.slice(5) : entry.id;
  const record: WearRecord = { id: recordId, outfitId: '', garmentIds: ids.slice(), date: date, feedback: entry.feedback };
  return { diary: old ? diary.map((item: DiaryEntry) => item.id === entry.id ? saved : item) : [saved].concat(diary),
    records: [record].concat(records.filter((item: WearRecord) => !relatedRecord(entry, item))).slice(0, 100),
    garments: adjustCounts(garments, old && wasCounted(old, records) ? old.garmentIds : [], ids), error: '' };
}

export function removeDiary(diary: DiaryEntry[], records: WearRecord[], garments: Garment[], id: string): DiaryMutation {
  const old: DiaryEntry | undefined = diary.find((entry: DiaryEntry) => entry.id === id);
  if (!old) { return { diary: diary, records: records, garments: garments, error: '' }; }
  return { diary: diary.filter((entry: DiaryEntry) => entry.id !== id),
    records: records.filter((record: WearRecord) => !relatedRecord(old, record)),
    garments: adjustCounts(garments, wasCounted(old, records) ? old.garmentIds : [], []), error: '' };
}
