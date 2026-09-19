import { UIExtensionContentSession } from '@kit.AbilityKit';
import { LiveFormExtensionAbility, LiveFormInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Garment, DemoSnapshot } from '../model/Wardrobe';
import { readSnapshot } from '../service/DemoRepository';
import { activeGarments } from './CardData';

export default class TodayLiveAbility extends LiveFormExtensionAbility {
  onLiveFormCreate(info: LiveFormInfo, session: UIExtensionContentSession): void {
    const storage: LocalStorage = new LocalStorage();
    storage.setOrCreate('formId', info.formId);
    storage.setOrCreate('rect', info.rect);
    storage.setOrCreate('items', new Array<Garment>());
    storage.setOrCreate('caption', '今日穿搭');
    // 官方要求 loadContent 在此生命周期同步调用；数据加载放在页面创建之后，避免互动卡片白屏。
    try { session.loadContent('widget/TodayLiveCard', storage); }
    catch (error) { hilog.error(0x1200, 'YiDaCard', 'Live card content failed'); return; }
    try {
      const snapshot: DemoSnapshot = readSnapshot(this.context.filesDir);
      storage.set('items', activeGarments(snapshot));
      storage.set('caption', snapshot.occasion + ' · ' + snapshot.temperature + '℃');
    } catch (error) { hilog.warn(0x1200, 'YiDaCard', 'Live card snapshot unavailable'); }
  }
}
