import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardData, cardData } from './CardData';
import { readSnapshot } from '../service/DemoRepository';

export default class TodayFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData { return this.binding(); }

  onUpdateForm(formId: string): void {
    // API 26 的摇一摇由系统触发 onUpdateForm。常规数据同步走 updateForm，避免保存衣物时自动展开卡片。
    formProvider.updateForm(formId, this.binding()).then(() => this.expand(formId)).catch(() => {
      hilog.warn(0x1200, 'YiDaCard', 'Card update failed');
    });
  }

  onFormEvent(formId: string, message: string): void {
    try {
      const params: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      if (params.message === 'expand') { this.expand(formId); }
    } catch (error) { hilog.warn(0x1200, 'YiDaCard', 'Invalid card event'); }
  }

  onAcquireFormState(): formInfo.FormState { return formInfo.FormState.READY; }

  private binding(): formBindingData.FormBindingData {
    let data: CardData = { caption: '今日穿搭', garmentName: '请打开应用查看衣橱', imageKey: '', count: 0, hasOutfit: false };
    try { data = cardData(readSnapshot(this.context.filesDir)); }
    catch (error) { hilog.warn(0x1200, 'YiDaCard', 'Snapshot unavailable'); }
    return formBindingData.createFormBindingData(data);
  }

  private async expand(formId: string): Promise<void> {
    try {
      const rect: formInfo.Rect = await formProvider.getFormRect(formId);
      if (rect.width <= 0 || rect.height <= 0) { return; }
      await formProvider.requestOverflow(formId, {
        area: { left: 0, top: -20, width: rect.width, height: rect.height + 40 }, duration: 3500
      });
    } catch (error) {
      // 不支持场景动效的桌面仍保留普通卡片以及直达应用入口。
      const cause: BusinessError = error as BusinessError;
      hilog.warn(0x1200, 'YiDaCard', 'Live card unavailable: %{public}d %{public}s', cause.code, cause.message);
    }
  }
}
