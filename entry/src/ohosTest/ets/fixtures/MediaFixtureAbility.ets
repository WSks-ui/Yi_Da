import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

// 仅由 ohosTest HAP 打包；正式 entry 模块没有该入口或相册写入权限。
export default class MediaFixtureAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/MediaFixturePage');
  }
}
