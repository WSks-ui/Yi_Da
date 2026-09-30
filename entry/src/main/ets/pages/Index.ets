import { abilityAccessCtrl, common, ConfigurationConstant, PermissionRequestResult } from '@kit.AbilityKit';
import { formProvider, formBindingData } from '@kit.FormKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Category, CATEGORIES, Garment, GarmentStatus, STATUSES, OCCASIONS, Outfit, OutfitRequest,
  Recommendation, DemoSnapshot, WearRecord, garmentImage, copyGarment,
  PreferenceProfile, emptyProfile, FITS, PALETTES, STYLES, DiaryEntry, TryOnTask, Membership,
  BodyProfile, emptyMembership, emptyBodyProfile, completeness, trialDaysLeft, CityOption, CITIES, SEASONS } from '../model/Wardrobe';
import { initialSnapshot, demoGarments } from '../data/DemoData';
import { DemoRepository, readSnapshot, validateSnapshot } from '../service/DemoRepository';
import { localDay, recordedDays, saveDiary, removeDiary, DiaryMutation } from '../service/WearHistory';
import { eligible, recommend, replaceGarment } from '../service/OutfitEngine';
import { Theme, Type } from '../components/Theme';
import { MaterialSupport, sheetMaterial, capsuleMaterial, HdsMaterialSupport, DockItem } from '../components/MaterialKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { WeatherService, WeatherSnapshot } from '../service/WeatherService';
import { HomePage } from './HomePage';
import { HomeBackdrop } from '../components/HomeBackdrop';
import { cutoutGarment, cutoutSupported, cutoutInFlight } from '../service/GarmentCutout';
import { OutfitStudioPage } from './OutfitStudioPage';
import { OutfitDetailPage } from './OutfitDetailPage';
import { DiaryPage } from './DiaryPage';
import { TryOnPage } from './TryOnPage';
import { AssistantSheet, AssistantMessage, AssistantMessageRole } from './AssistantSheet';
import { ProfilePage, BodyProfileSheet } from './ProfilePage';
import { SyncTransferSheet } from './SyncTransferSheet';
import { CityPickerSheet } from './CityPicker';
import { WardrobePage } from './WardrobePage';
import { AddGarmentSheet, GarmentDraft, emptyDraft } from './AddGarmentSheet';
import { cardData, CardData } from '../widget/CardData';
import { activeImageUri as activeImportImage, ImportFailureStep, ImportItem, ImportPhase } from '../model/GarmentImport';
import { applyCategory, applyDraft, applyMaxTemp, applyMinTemp, canSave,
  isActivePhase, isPending, makeSessionId, needsSkipConfirm, nextDraftFileKey,
  remainingCapacity, saveFailed, summaryOf } from '../service/GarmentImport';
import { ImportHost, ImportSession } from '../service/GarmentImportRunner';
import { GarmentImportController } from '../service/GarmentImportController';
import { CommitCallbacks, SnapshotCommit } from '../service/SnapshotCommit';
import { GarmentImportPage } from './GarmentImportPage';
import { bundledPhotoId, bundledPhotoSource, importBundledGarmentPhoto } from '../service/BundledGarmentPhotos';
import { GarmentRecognition, recognitionSummary, RECOGNITION_SOURCE_PIXEL_COLOR }
  from '../service/GarmentRecognition';
import { recognizeGarmentPhoto as recognizeGarment } from '../service/GarmentRecognitionImage';
import { garmentModel } from '../service/OnDeviceGarmentModel';
import { ClothingCandidate } from '../service/OpenImageClothing';
import { runOutfitAgent, OutfitAgentContext, OutfitAgentSession } from '../service/OutfitAgent';
import { createSyncEnvelope, SyncEnvelope } from '../service/WardrobeSync';
import { commitWardrobeMigrationCandidate, MigrationPreparationResult,
  prepareWardrobeMigration, WardrobeMigrationCandidate } from '../service/WardrobeMigration';
import { createCoreFileMigrationTargetAdapter, exportWardrobeMigrationWithPicker, MigrationPickerResult,
  selectMigrationPackageWithPicker } from '../service/WardrobeMigrationHost';
import { findDemoScene, saveDemoTask } from '../service/TryOnDemo';
import { DadaEntry } from '../components/DadaOrb';
import { AssistantProposal, DadaAction, DadaContext, DadaPage, DadaState, DADA_WELCOME, TRY_ON_BOUNDARY,
  dadaGuide, validateAssistantOutfit } from '../service/DadaContext';
import { TryOnCommand, TryOnStage, presentationRunning } from '../service/TryOnPresentationController';

interface TextPair {
  title: string;
  subtitle: string;
}

interface StatValue {
  label: string;
  value: number;
}

interface ImportRecognitionHint {
  taskId: string;
  revision: number;
  originalUri: string;
  color: string;
  categoryIndex: number;
  subcategory: string;
  message: string;
}

// 偏好测验的一道题。选项用文字卡呈现，点击后自动进入下一题，并保留“上一题”和“不确定”。
interface QuizQuestion {
  title: string;
  hint: string;
  options: string[];
}

const QUIZ: QuizQuestion[] = [
  { title: '你更喜欢哪种版型？', hint: '可以多选，也可以稍后在档案里修改', options: FITS },
  { title: '配色上你更常穿哪一类？', hint: '按平时最常穿的颜色？', options: PALETTES },
  { title: '这些风格里，你会穿哪些？', hint: '可以多选', options: STYLES },
  { title: '对叠穿的态度？', hint: '叠穿指外套、衬衫叠搭等多层穿法', options: ['喜欢', '无所谓', '不喜欢'] },
  { title: '对图案和配饰的接受度？', hint: '印花、图案单品与配饰', options: ['喜欢', '无所谓', '不喜欢'] },
  { title: '出门时你更看重什么？', hint: '只会影响推荐顺序，不会排除衣物', options: ['舒适', '正式感', '个性表达', '显瘦'] }
];

const CONTENT_MAX_WIDTH: number = 840;

@Entry
@Component
struct Index {
  @StorageLink('cardOpenSequence') @Watch('onCardOpen') cardOpenSequence: number = 0;
  @StorageProp('appForeground') @Watch('onDadaForegroundChanged') foreground: boolean = true;
  @State tab: number = 0;
  @State garments: Garment[] = [];
  @State saved: Outfit[] = [];
  @State records: WearRecord[] = [];
  @State plans: Outfit[] = [];
  @State occasion: string = '上课';
  @State temperature: number = 24;
  @State lockedIds: string[] = [];
  @State excludedIds: string[] = [];
  @State activeIds: string[] = [];
  @State search: string = '';
  @State filterCategory: string = '全部';
  @State filterStatus: string = '全部状态';
  @State showSaved: boolean = false;
  @State explanation: string = '';
  @State notice: string = '';
  @State sheet: string = '';
  @State showSheet: boolean = false;
  @State selectedItem: Garment = demoGarments()[0];
  @State selectedLook: Outfit = { id: '', garmentIds: [], occasion: '上课', temperature: 24, reason: '', name: '', isCustom: false, savedAt: '' };
  // 添加衣物的表单草稿，交给 AddGarmentSheet 维护。
  @State draft: GarmentDraft = emptyDraft();
  @State editingGarment: boolean = false;
  private draftImages: string[] = [];
  // 单件表单的图片状态：原图与抠图结果都由本页持有，弹层关闭时统一清理。
  @State importing: boolean = false;
  @State cuttingOut: boolean = false;
  @State originalDraftUri: string = '';
  @State cutoutDraftUri: string = '';
  // 单件表单的保存忙碌态：落盘成功前不关弹层、不交图片所有权。
  @State savingGarment: boolean = false;
  @State readBlocked: boolean = false;
  // ---- 批量录入：队列与在途任务的唯一所有者是本页 ----
  @State importItems: ImportItem[] = [];
  @State importIndex: number = 0;
  // 图片主色建议只属于当前导入会话，不落入衣橱快照；真正采用时仍通过会话编辑草稿。
  @State importRecognitionHints: ImportRecognitionHint[] = [];
  @State recognizingImportTaskId: string = '';
  // 单件换图的文件标识前缀。每次换图取一个不可复用的键，不复用草稿数组长度。
  private importSessionId: string = '';
  // 生产导入链：items / index / 串行拷贝 / 抠图 / 失效清理都由它持有。
  // 页面只保存它发布的快照，不再维护第二份可独立修改的队列。
  private importCtl: GarmentImportController | undefined = undefined;
  private orphanSwept: boolean = false;
  // 启动遗留清理是否已经结束。清理完成前不允许建立新的导入文件，
  // 否则新文件可能被当成遗留文件删掉。
  private sweepDone: boolean = false;
  // 快照提交锁：见 service/SnapshotCommit.ets。顺序是先落盘、再发布、后处理延后项。
  // 只有仓储写队列并不能阻止旧快照覆盖新数据——两个调用方各自构造全量快照后，后写的那个会赢。
  private commitLock: SnapshotCommit = SnapshotCommit.create();
  private commitInFlight: boolean = false;
  // 手动迁移先写图片、后落盘快照；图片写入阶段同样禁止其它全量快照提交。
  private migrationBusy: boolean = false;
  // 待重试的变更：顶部提示条只重试这一次变更，不提交任何残留候选。
  private pendingRetry: (() => void) | undefined = undefined;
  // 每次新操作、跳过、退出或重置都会推进代数，令旧失败回调失效，避免覆盖后续输入。
  private retryGeneration: number = 0;
  // 卡片唤起遇到导入在途时延后到队列稳定，再走同一套退出确认与回今日动画。
  private pendingImportCardOpen: boolean = false;
  // 卡片请求绑定发起时的导入会话；会话退出或重建后，旧请求不得操作新队列。
  private pendingImportCardSession: ImportSession | undefined = undefined;
  // 发布回调可能连续触发，分别用两个标志避免重复排队和重复弹出退出确认。
  private pendingImportExitScheduled: boolean = false;
  private importExitDialogOpen: boolean = false;
  // 偏好档案： 表示未开始，1..QUIZ.length 表示答题中，QUIZ.length+1 表示结果页。
  @State profile: PreferenceProfile = emptyProfile();
  @State diary: DiaryEntry[] = [];
  @State tryOnTasks: TryOnTask[] = [];
  // 进入试穿页时选中的固定样片场景；历史记录入口会把对应场景带进来。
  @State tryOnSceneId: string = 'denim_skirt';
  @State membership: Membership = emptyMembership();
  @State body: BodyProfile = emptyBodyProfile();
  // 已添加的桌面卡片数量，用于「我的」展示真实状态。
  @State cardSpaces: number = 0;
  // 用户选择的城市名，落盘后下次启动仍生效。
  @State city: string = '';
  @State agentMessages: AssistantMessage[] = [];
  @State agentOutfits: Outfit[] = [];
  private agentLatestOutfit: Outfit | undefined = undefined;
  @State dadaState: DadaState = DadaState.IDLE;
  @State dadaFeedback: string = '';
  @State assistantBusy: boolean = false;
  @State assistantContext: DadaContext = { page: DadaPage.TODAY, key: 'today', objectId: '' };
  private assistantProposal: AssistantProposal | undefined = undefined;
  private assistantProposalSequence: number = 0;
  private pendingDadaAction: DadaAction | undefined = undefined;
  private pendingDadaInput: string = '';
  @State tryOnCommand: TryOnCommand = { id: 0, action: 'start', sceneId: 'denim_skirt' };
  @State tryOnStage: TryOnStage = TryOnStage.IDLE;
  private tryOnCommandSequence: number = 0;
  // 主路由：tabs 为底部四入口；其余值打开对应的独立页面。
  @State mainRoute: string = 'tabs';
  // 弹层内容的入场开关：openSheet 里置回false，延后一帧置 true，触发内容淡入。
  @State sheetEntered: boolean = false;
  // 程序化切页签时内容的不透明度：1 显示、 退场。
  @State tabPhase: number = 1;
  // 画布离开后保留会话草稿；显式保存的作品由 saved 持久化，重启后可从收藏再编辑。
  @State studioDraft: Outfit | undefined = undefined;
  // 官方 HdsTabs 需要控制器对象。
  private tabsController: HdsTabsController = new HdsTabsController();
  // 真实天气快照；available=false 时界面显示手动温度与来源说明。
  @State weather: WeatherSnapshot = { available: false, city: '', condition: '', tempMin: 0, tempMax: 0, source: '手动温度' };
  @State quizStep: number = 0;
  @State quizFits: string[] = [];
  @State quizPalettes: string[] = [];
  @State quizStyles: string[] = [];
  @State quizLayering: string = '';
  @State quizPattern: string = '';
  @State quizPriority: string = '';
  private repository: DemoRepository | undefined = undefined;
  private alive: boolean = false;
  private cardQueue: Promise<void> = Promise.resolve();
  private todayScroller: Scroller = new Scroller();
  private routeScroller: Scroller = new Scroller();
  private routeHistory: string[] = [];
  private weatherRequest: number = 0;
  private pendingWearId: string = '';
  private recordingWear: boolean = false;
  private agentMessageSequence: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    const context: common.UIAbilityContext = this.context();
    this.repository = new DemoRepository(context.filesDir);
    try {
      this.restore(readSnapshot(context.filesDir));
      // 只有快照确实读成功、且这次启动还没清理过，才允许清理上一轮遗留的批量临时文件。
      // readBlocked 时禁止清理：读失败时保留集合不可信，宁可留文件也不能删掉还引用着的图片。
      this.sweepOrphans();
    } catch (error) {
      this.restore(initialSnapshot());
      this.readBlocked = true;
      this.notice = '本地记录无法读取。已显示示例衣橱，可在“我的”导入备份或重置';
      hilog.error(0x1200, 'YiDa', 'Read demo snapshot failed');
    }
    this.refreshWeather();
  }

  // 启动遗留清理只做一次：本次会话建立的新文件属于当前队列，不能被当成遗留。
  private sweepOrphans(): void {
    if (this.orphanSwept || !this.repository) { return; }
    this.orphanSwept = true;
    const snapshot: DemoSnapshot = this.snapshot();
    this.repository.sweepOrphans(snapshot).then((removed: number) => {
      if (removed > 0) { hilog.info(0x1200, 'YiDa', 'Swept %{public}d orphan import files', removed); }
    }).catch(() => { hilog.warn(0x1200, 'YiDa', 'Orphan sweep failed'); })
      .then(() => { this.sweepDone = true; });
  }

  // 真实天气是加分项而不是依赖：拿不到就继续用手动温度，并在界面上说明来源。
  private refreshWeather(): void {
    const context: common.UIAbilityContext = this.context();
    const request: number = ++this.weatherRequest;
    WeatherService.refresh(context).then((snapshot: WeatherSnapshot) => {
      if (!this.alive || request !== this.weatherRequest) { return; }
      this.weather = snapshot;
      // 拿到当日温度区间时，用区间中值作为推荐温度，比固定值更贴近真实天气。
      if (snapshot.available && snapshot.tempMax >= snapshot.tempMin) {
        const mid: number = Math.round((snapshot.tempMin + snapshot.tempMax) / 2);
        this.applyTemperature(mid);
      }
    }).catch(() => {
      hilog.warn(0x1200, 'YiDa', 'Weather refresh failed');
    });
  }

  // 用户点“使用当前位置”后才请求前台粗略定位；拒绝或设备缺 Kit 时继续保留手动城市。
  // request 代数使权限弹窗期间的旧天气回调失效，避免旧城市结果覆盖用户刚改的温度。
  private async refreshWeatherAtLocation(): Promise<void> {
    const request: number = ++this.weatherRequest;
    try {
      const permission: PermissionRequestResult = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(this.context(), ['ohos.permission.APPROXIMATELY_LOCATION']);
      if (!this.alive || request !== this.weatherRequest) { return; }
      if (permission.authResults.length === 0 || permission.authResults[0] !== 0) {
        this.toast('未取得定位授权，可继续手动选择城市和温度');
        return;
      }
      const snapshot: WeatherSnapshot = await WeatherService.refresh(this.context(), true);
      if (!this.alive || request !== this.weatherRequest) { return; }
      this.weather = snapshot;
      if (snapshot.available && snapshot.tempMax >= snapshot.tempMin) {
        this.applyTemperature(Math.round((snapshot.tempMin + snapshot.tempMax) / 2));
        if (snapshot.city !== '当前位置') {
          this.toast('未取得当前位置，已使用手动城市的天气');
        }
      } else {
        this.toast(snapshot.source);
      }
    } catch (error) {
      if (this.alive && request === this.weatherRequest) {
        this.toast('当前设备无法定位，可继续手动选择城市和温度');
      }
    }
  }

  // 天气是异步到达的：提交锁期间到达的温度不能中途改掉正在落盘的快照。
  // 先记下来，等本次提交结束后再用最新完整状态应用并补存。
  private applyTemperature(mid: number): void {
    if (!Number.isFinite(mid)) { return; }
    // 天气卡保留服务给出的实际区间；推荐引擎支持 -20~45℃，极端值只在推荐温度上限幅。
    const next: number = Math.max(-20, Math.min(45, Math.round(mid)));
    if (next === this.temperature) { return; }
    if (this.commitInFlight || this.migrationBusy) { this.commitLock.deferTemperature(next); return; }
    this.temperature = next;
    this.regenerate();
    this.persist();
  }

  aboutToDisappear(): void { this.alive = false; }
  private onCardOpen(): void {
    // 提交进行中不抢导航：等落盘结束后再回到今日，避免把正在保存的草稿丢掉。
    if (this.navigating()) { this.commitLock.deferCardOpen(); return; }
    this.handleCardOpen();
  }

  // 卡片入口与普通返回共用导入退出保护。导入有在途任务时先记住请求，
  // 不能直接切路由，否则 COPYING/CUTTING 的迟到结果会失去所有者。
  private handleCardOpen(): void {
    if (this.mainRoute === 'garmentImport') {
      this.pendingImportCardOpen = true;
      this.pendingImportCardSession = this.importCtl === undefined ? undefined : this.importCtl.currentSession();
      // Picker 仍在系统界面中时先只记录请求，等 pickImportPhotos 的 finally 统一处理。
      if (!this.importing) { this.importExit(true); }
      return;
    }
    this.pendingImportCardOpen = false;
    this.returnToToday();
  }

  // 目标是今日页时仍使用现有 closeRoute/switchTab 的动画时序，避免卡片直达瞬切。
  private returnToToday(): void {
    if (this.mainRoute === 'tabs') {
      this.showSheet = false; this.routeHistory = [];
      if (this.tab !== 0) { this.switchTab(0); }
      this.todayScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      return;
    }
    animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => {
      this.mainRoute = 'tabs'; this.routeHistory = []; this.showSheet = false;
      if (this.tab !== 0) { this.switchTab(0); }
    });
    this.todayScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  // 状态栏文字颜色。SystemBarStyle.statusBarContentColor 只接受字符串、不能用资源引用。
  // 所以这里按深浅色模式手工取色，与color.json 里的 text_primary 保持一致。
  private statusBarInk(): string {
    const dark: boolean = this.context().config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return dark ? '#FFF7F1F3' : '#FF2B2225';
  }

  private toast(message: string): void {
    if (!this.alive) { return; }
    try { this.getUIContext().getPromptAction().showToast({ message: message }); }
    catch (error) { hilog.warn(0x1200, 'YiDa', 'Toast unavailable'); }
  }
  private openSheet(name: string): void {
    this.sheet = name;
    this.showSheet = true;
    // 弹层内容的入场开关：先置回初始态，延后一帧再置true，属性变化才有起点。
    // 延迟 50ms 是为了让半模态自身的上滑先起势，内容再跟上，读起来是一件事而不是两件。
    this.sheetEntered = false;
    setTimeout(() => { this.sheetEntered = true; }, 50);
  }

  private dadaContext(): DadaContext {
    let page: DadaPage = DadaPage.TODAY;
    let objectId: string = '';
    if (this.mainRoute === 'garmentImport') {
      page = DadaPage.IMPORT;
      const item: ImportItem | undefined = this.importItems[this.importIndex];
      objectId = item === undefined ? '' : item.id + ':' + item.revision + ':' + item.originalUri;
    } else if (this.mainRoute === 'tryOn') { page = DadaPage.TRY_ON; objectId = this.tryOnSceneId; }
    else if (this.mainRoute === 'outfitStudio') { page = DadaPage.DIY; }
    else if (this.mainRoute === 'outfitDetail') { page = DadaPage.DETAIL; objectId = this.selectedLook.id; }
    else if (this.mainRoute === 'diary') { page = DadaPage.DIARY; }
    else if (this.tab === 1) { page = DadaPage.WARDROBE; }
    else if (this.tab === 2) { page = DadaPage.OUTFIT; }
    else if (this.tab === 3) { page = DadaPage.PROFILE; }
    return { page: page, key: page + ':' + objectId, objectId: objectId };
  }

  private openAssistant(): void {
    if (!this.foreground || this.showSheet || this.navigating() || this.importExitDialogOpen || this.importing) { return; }
    const context: DadaContext = this.dadaContext();
    if (this.assistantContext.key !== context.key || this.agentMessages.length === 0) {
      this.agentMessages = [{ id: 'agent_welcome', role: AssistantMessageRole.ASSISTANT,
        text: DADA_WELCOME }];
      this.agentOutfits = []; this.assistantProposal = undefined; this.agentLatestOutfit = undefined;
      this.dadaFeedback = ''; this.dadaState = DadaState.IDLE;
    }
    this.assistantContext = context;
    this.openSheet('assistant');
  }

  private dadaVisualState(): DadaState {
    if (this.mainRoute === 'tryOn' && presentationRunning(this.tryOnStage)) {
      return this.tryOnStage === TryOnStage.REVEALING ? DadaState.COMPLETE : DadaState.WORKING;
    }
    if (this.recognizingImportTaskId.length > 0) { return DadaState.WORKING; }
    // 切项或退出后，不把旧分析的处理态留在其它页面的顶栏。
    if (this.assistantContext.key !== this.dadaContext().key || this.dadaState === DadaState.WORKING) {
      return DadaState.IDLE;
    }
    return this.dadaState;
  }

  private onDadaForegroundChanged(): void {
    if (this.foreground) { return; }
    // 面板关闭与后台回调可能交错；后台丢弃尚未启动的请求，回来后必须由用户重新点击。
    this.pendingDadaAction = undefined; this.pendingDadaInput = '';
    this.tryOnCommand = { id: 0, action: 'start', sceneId: this.tryOnSceneId };
  }

  private addAgentMessage(role: AssistantMessageRole, text: string): void {
    this.agentMessageSequence++;
    this.agentMessages = this.agentMessages.concat([{ id: `agent_${this.agentMessageSequence}`,
      role: role, text: text }]);
  }

  private submitAssistant(input: string): void {
    if (this.assistantBusy || this.recognizingImportTaskId.length > 0 || input.trim().length === 0) { return; }
    if (this.assistantContext.key !== this.dadaContext().key) {
      this.dadaFeedback = '当前页面内容已变化，请关闭后重新打开搭搭。'; return;
    }
    this.addAgentMessage(AssistantMessageRole.USER, input);
    const page: DadaPage = this.assistantContext.page;
    if (page === DadaPage.IMPORT) {
      if (input.indexOf('分析') >= 0 || input.indexOf('识别') >= 0) { this.dadaAction(DadaAction.ANALYZE, ''); }
      else if (input.indexOf('颜色') >= 0 && input.indexOf('采用') >= 0) { this.dadaAction(DadaAction.USE_COLOR, ''); }
      else if (input.indexOf('品类') >= 0 && input.indexOf('采用') >= 0) { this.dadaAction(DadaAction.USE_CATEGORY, ''); }
      else { this.addAgentMessage(AssistantMessageRole.ASSISTANT, dadaGuide(page) + ' 请先完成或退出录入，再切换到其它页面。'); }
      return;
    }
    if (page === DadaPage.TRY_ON) {
      if (input.indexOf('对比') >= 0) { this.dadaAction(DadaAction.COMPARE, ''); }
      else if (input.indexOf('演示') >= 0 || input.indexOf('试穿') >= 0) {
        const sceneId: string = input.indexOf('红') >= 0 ? 'red_dress' : input.indexOf('蓝') >= 0 ? 'navy_top' : this.tryOnSceneId;
        this.dadaAction(DadaAction.TRY_ON, sceneId);
      } else { this.addAgentMessage(AssistantMessageRole.ASSISTANT, dadaGuide(page)); }
      return;
    }
    if (page === DadaPage.DIY || page === DadaPage.DETAIL || page === DadaPage.DIARY || page === DadaPage.PROFILE) {
      this.addAgentMessage(AssistantMessageRole.ASSISTANT, dadaGuide(page)); return;
    }
    if (!/今天|明天|上课|课堂|约会|展示|正式|答辩|汇报|社团|活动|穿|搭配|上装|上衣|换鞋|一双鞋|一套|冷|凉|热|暖|降温|升温|度|℃|帮助|能做什么|怎么用|指令/.test(input)) {
      this.addAgentMessage(AssistantMessageRole.ASSISTANT, '我现在能帮你按场合、温度推荐，或在上一套建议里替换单品。试试“上课，24度”或“换一件上装”。'); return;
    }
    // 连续追问读上一轮提案的条件，不读首页条件；聊天本身不得发布业务状态或写盘。
    const previous: AssistantProposal | undefined = this.assistantProposal;
    const context: OutfitAgentContext = { garments: this.garments, profile: this.profile, body: this.body,
      occasion: previous === undefined ? this.occasion : previous.occasion,
      temperature: previous === undefined ? this.temperature : previous.temperature, lockedIds: this.lockedIds,
      excludedIds: this.excludedIds };
    const session: OutfitAgentSession = { latestOutfit: this.agentLatestOutfit };
    const result = runOutfitAgent(input, context, session);
    this.assistantProposalSequence++;
    this.assistantProposal = { id: this.assistantProposalSequence, contextKey: this.assistantContext.key,
      occasion: result.occasion, temperature: result.temperature, outfits: result.recommendation.outfits };
    this.agentLatestOutfit = result.latestOutfit;
    this.agentOutfits = result.recommendation.outfits.slice(0, 3);
    this.dadaState = this.agentOutfits.length > 0 ? DadaState.COMPLETE : DadaState.IDLE;
    this.dadaFeedback = this.agentOutfits.length > 0 ? '建议已准备好，采用前可以继续调整。' : '';
    this.addAgentMessage(AssistantMessageRole.ASSISTANT, result.reply);
  }

  private async applyAgentOutfit(look: Outfit): Promise<void> {
    const proposal: AssistantProposal | undefined = this.assistantProposal;
    if (this.assistantBusy || this.readBlocked || this.businessBusy() || proposal === undefined) { return; }
    if (proposal.contextKey !== this.dadaContext().key || !proposal.outfits.some((item: Outfit) => item.id === look.id)) {
      this.dadaFeedback = '这份建议已经过期，请重新提问。'; this.dadaState = DadaState.ERROR; return;
    }
    const request: OutfitRequest = this.request();
    request.occasion = proposal.occasion; request.temperature = proposal.temperature;
    const source: Outfit | undefined = proposal.outfits.find((item: Outfit) => item.id === look.id);
    const checked: Outfit | undefined = source === undefined ? undefined : validateAssistantOutfit(source, this.garments, request);
    if (checked === undefined) {
      this.dadaFeedback = '衣物状态或条件已变化，请重新生成建议。'; this.dadaState = DadaState.ERROR; return;
    }
    this.invalidateRetry(); this.assistantBusy = true;
    const base: DemoSnapshot = this.snapshot();
    const candidate: DemoSnapshot = { version: base.version, garments: base.garments, saved: base.saved,
      records: base.records, occasion: checked.occasion, temperature: checked.temperature,
      activeIds: checked.garmentIds.slice(), profile: base.profile, diary: base.diary,
      tryOnTasks: base.tryOnTasks, membership: base.membership, body: base.body, city: base.city };
    try {
      const success: boolean = await this.commit(candidate, () => {
        this.occasion = checked.occasion; this.temperature = checked.temperature;
        this.activeIds = checked.garmentIds.slice(); this.regenerate();
        this.plans = [checked].concat(this.plans.filter((item: Outfit) => item.id !== checked.id));
      }, () => {
        this.refreshCard(); this.dadaState = DadaState.COMPLETE; this.dadaFeedback = '已采用这套搭配';
        if (this.sheet === 'assistant') { this.showSheet = false; }
        this.toast('已采用这套搭配');
      }, () => {
        if (this.assistantProposal?.id === proposal.id && proposal.contextKey === this.dadaContext().key) {
          this.applyAgentOutfit(look).catch(() => {});
        }
      });
      if (!success) { this.dadaState = DadaState.ERROR; this.dadaFeedback = '搭配尚未保存，可再次点击采用重试。'; }
    } finally { this.assistantBusy = false; }
  }

  private dadaAction(action: DadaAction, input: string): void {
    if (this.assistantBusy || this.navigating() || this.assistantContext.key !== this.dadaContext().key) { return; }
    const page: DadaPage = this.assistantContext.page;
    if (action === DadaAction.GUIDE) { this.addAgentMessage(AssistantMessageRole.ASSISTANT, dadaGuide(page)); return; }
    if (page === DadaPage.IMPORT) {
      if (action === DadaAction.ANALYZE) { this.dadaAnalyzeCurrent(); }
      else if (action === DadaAction.USE_COLOR || action === DadaAction.USE_CATEGORY) {
        const current: ImportItem | undefined = this.importItems[this.importIndex];
        if (this.readBlocked || current === undefined || isActivePhase(current.phase) ||
          current.phase === ImportPhase.SAVED || current.phase === ImportPhase.SKIPPED) {
          this.dadaFeedback = '当前任务不可编辑，请选择一张待录入的照片。'; return;
        }
        const hint: ImportRecognitionHint | undefined = this.importRecognitionHint();
        if (hint === undefined || (action === DadaAction.USE_COLOR ? hint.color.length === 0 : hint.categoryIndex < 0)) {
          this.dadaFeedback = '还没有可采用的建议，请先分析当前照片。'; return;
        }
        if (action === DadaAction.USE_COLOR) { this.useRecognizedColor(this.importIndex); }
        else { this.useRecognizedCategory(this.importIndex); }
        this.dadaFeedback = '建议已填入当前草稿，请继续确认并保存。';
      } else { this.dadaFeedback = '请先完成或退出录入，再切换到其它页面。'; }
      return;
    }
    if (action === DadaAction.RECOMMEND) { this.submitAssistant(input); return; }
    if (action === DadaAction.TRY_ON || action === DadaAction.COMPARE || action === DadaAction.OPEN_IMPORT) {
      if (presentationRunning(this.tryOnStage)) { this.dadaFeedback = '演示正在进行，请先等待或取消。'; return; }
      this.pendingDadaAction = action; this.pendingDadaInput = input;
      this.showSheet = false; // 请求在半模态真正消失后分派，避免页面启动时被面板遮住。
    }
  }

  private async dadaAnalyzeCurrent(): Promise<void> {
    if (this.recognizingImportTaskId.length > 0) { return; }
    const key: string = this.assistantContext.key;
    this.dadaState = DadaState.WORKING; this.dadaFeedback = '正在分析当前照片…';
    await this.recognizeImportColor(this.importIndex);
    if (!this.alive || key !== this.dadaContext().key) { return; }
    const hint: ImportRecognitionHint | undefined = this.importRecognitionHint();
    this.dadaState = hint !== undefined && (hint.color.length > 0 || hint.categoryIndex >= 0) ? DadaState.COMPLETE : DadaState.ERROR;
    this.dadaFeedback = hint === undefined ? '当前照片尚未就绪，请等待导入完成。' : hint.message;
  }

  private onSheetClosed(): void {
    // 只在添加表单消失时回收它拥有的临时图片；搭搭面板必须保留所有页面草稿。
    if (this.sheet === 'add') { this.clearDraft(); }
    const action: DadaAction | undefined = this.pendingDadaAction;
    const input: string = this.pendingDadaInput;
    this.pendingDadaAction = undefined; this.pendingDadaInput = '';
    if (!this.alive || !this.foreground || this.navigating() || action === undefined ||
      this.assistantContext.key !== this.dadaContext().key) { return; }
    if (action === DadaAction.OPEN_IMPORT) { this.openAdd(); return; }
    this.tryOnCommandSequence++;
    const sceneId: string = findDemoScene(input) !== undefined ? input : this.tryOnSceneId;
    this.openTryOn(sceneId);
    this.tryOnCommand = { id: this.tryOnCommandSequence, action: action === DadaAction.COMPARE ? 'compare' : 'start', sceneId: sceneId };
  }

  private restore(snapshot: DemoSnapshot): void {
    this.garments = snapshot.garments; this.saved = snapshot.saved; this.records = snapshot.records;
    this.occasion = snapshot.occasion; this.temperature = snapshot.temperature; this.activeIds = snapshot.activeIds;
    this.profile = snapshot.profile ? snapshot.profile : emptyProfile();
    this.diary = snapshot.diary ? snapshot.diary : [];
    this.tryOnTasks = snapshot.tryOnTasks ? snapshot.tryOnTasks : [];
    this.membership = snapshot.membership ? snapshot.membership : emptyMembership();
    this.body = snapshot.body ? snapshot.body : emptyBodyProfile();
    this.city = snapshot.city ? snapshot.city : '';
    // 已选过城市就把它作为手动坐标，天气取不到时温度仍有依据。
    const saved: CityOption | undefined = CITIES.find((item: CityOption) => item.name === this.city);
    if (saved !== undefined) { WeatherService.setManualCity(saved); }
    else { WeatherService.clearManualCity(); }
    this.regenerate();
  }

  private request(): OutfitRequest {
    return { occasion: this.occasion, temperature: this.temperature, lockedIds: this.lockedIds,
      excludedIds: this.excludedIds, profile: this.profile, body: this.body };
  }

  private regenerate(): void {
    const result: Recommendation = recommend(this.garments, this.request());
    this.plans = result.outfits; this.explanation = result.explanation;
    const selectedIndex: number = this.plans.findIndex((look: Outfit) => look.garmentIds.join(',') === this.activeIds.join(','));
    if (selectedIndex < 0) {
      // 多轮替换后的合法组合未必位列前三。重新计算和重启时重新校验该组合，
      // 合法则保留用户已采用的选择，避免磁盘、首页与桌面卡片显示不同的搭配。
      const selected: Outfit = { id: '', garmentIds: this.activeIds.slice(), occasion: this.occasion,
        temperature: this.temperature, reason: '', name: '', isCustom: false, savedAt: '' };
      const checked: Outfit | undefined = validateAssistantOutfit(selected, this.garments, this.request());
      if (checked !== undefined) { this.plans = [checked].concat(this.plans); }
      else { this.activeIds = this.plans.length > 0 ? this.plans[0].garmentIds.slice() : []; }
    } else if (selectedIndex > 0) {
      // 重启及卡片直达时优先显示已选组合，使首页与桌面卡片保持一致。
      this.plans = [this.plans[selectedIndex]].concat(this.plans.filter((look: Outfit, index: number) => index !== selectedIndex));
    }
  }

  // 悬浮页签的四个入口。选中态用实心图标，未选中用描边，符合系统页签习惯。
  private dockItems(): DockItem[] {
    return [
      { icon: $r('sys.symbol.sun_max'), selectedIcon: $r('sys.symbol.sun_max_fill'), label: '今日' },
      { icon: $r('sys.symbol.shirt'), selectedIcon: $r('sys.symbol.hanger_and_towels'), label: '衣橱' },
      { icon: $r('sys.symbol.square_grid_2x2'), selectedIcon: $r('sys.symbol.grid'), label: '搭配' },
      { icon: $r('sys.symbol.person'), selectedIcon: $r('sys.symbol.person_fill'), label: '我的' }
    ];
  }

  private snapshot(): DemoSnapshot {
    // 只反映已发布的业务状态：候选不再挂在组件上做隐式覆盖。
    return { version: 1, garments: this.garments, saved: this.saved, records: this.records,
      occasion: this.occasion, temperature: this.temperature, activeIds: this.activeIds, profile: this.profile,
      diary: this.diary, tryOnTasks: this.tryOnTasks, membership: this.membership, body: this.body,
      city: this.city };
  }

  // 在已发布状态之上构造一份候选快照。候选只活在本次操作里，不写进组件字段。
  private withGarments(next: Garment[]): DemoSnapshot {
    const base: DemoSnapshot = this.snapshot();
    return { version: base.version, garments: next, saved: base.saved, records: base.records,
      occasion: base.occasion, temperature: base.temperature, activeIds: base.activeIds,
      profile: base.profile, diary: base.diary, tryOnTasks: base.tryOnTasks,
      membership: base.membership, body: base.body, city: base.city };
  }

  private withSaved(next: Outfit[]): DemoSnapshot {
    const base: DemoSnapshot = this.snapshot();
    return { version: base.version, garments: base.garments, saved: next, records: base.records,
      occasion: base.occasion, temperature: base.temperature, activeIds: base.activeIds,
      profile: base.profile, diary: base.diary, tryOnTasks: base.tryOnTasks,
      membership: base.membership, body: base.body, city: base.city };
  }

  private withDiary(change: DiaryMutation): DemoSnapshot {
    const base: DemoSnapshot = this.snapshot();
    return { version: base.version, garments: change.garments, saved: base.saved, records: change.records,
      occasion: base.occasion, temperature: base.temperature, activeIds: base.activeIds,
      profile: base.profile, diary: change.diary, tryOnTasks: base.tryOnTasks,
      membership: base.membership, body: base.body, city: base.city };
  }

  private withTryOnTasks(next: TryOnTask[]): DemoSnapshot {
    const base: DemoSnapshot = this.snapshot();
    return { version: base.version, garments: base.garments, saved: base.saved, records: base.records,
      occasion: base.occasion, temperature: base.temperature, activeIds: base.activeIds,
      profile: base.profile, diary: base.diary, tryOnTasks: next,
      membership: base.membership, body: base.body, city: base.city };
  }

  private withBody(next: BodyProfile, activeIds: string[]): DemoSnapshot {
    const base: DemoSnapshot = this.snapshot();
    return { version: base.version, garments: base.garments, saved: base.saved, records: base.records,
      occasion: base.occasion, temperature: base.temperature, activeIds: activeIds,
      profile: base.profile, diary: base.diary, tryOnTasks: base.tryOnTasks,
      membership: base.membership, body: next, city: base.city };
  }

  // ---- 快照提交：所有写入口都走这里 ----
  //
  // 顺序契约（本页与 service/SnapshotCommit.ets 共同保证）：
  //   1. 候选快照先落盘成功；
  //   2. 落盘成功后才 publish 新的业务状态；
  //   3. 最后才执行延后的天气、补存与导航。
  // 失败路径只登记 notice，绝不发布成功、绝不执行延后项。
  private commit(snapshot: DemoSnapshot,
    publish?: () => void, afterPublish?: () => void, retry?: () => void,
    preserveExistingRetry: boolean = false): Promise<boolean> {
    if (!this.repository) { return Promise.resolve(false); }
    // 业务请求不排队覆盖候选：调用方必须保留草稿并等待用户明确重试。
    if (this.migrationBusy || this.commitInFlight || this.commitLock.isLocked()) {
      if (this.alive) { this.toast('正在保存上一项，请稍候'); }
      return Promise.resolve(false);
    }
    this.commitInFlight = true;
    const hadRetry: boolean = this.pendingRetry !== undefined;
    const payload: string = JSON.stringify(snapshot);
    const callbacks: CommitCallbacks = {
      save: (data: string) => this.repository ? this.repository.savePayload(data) : Promise.reject(new Error('仓储尚未就绪')),
      publish: () => { if (publish !== undefined) { publish(); } },
      afterPublish: () => {
        this.commitInFlight = false;
        // 天气等纯 persist 成功时不能抹掉仍有效的业务失败入口；对应业务成功才清提示。
        if (!preserveExistingRetry || !hadRetry) {
          this.pendingRetry = undefined;
          this.retryGeneration++;
          if (this.alive) { this.notice = ''; }
        }
        this.afterPublish(afterPublish);
      },
      onFailure: (reason: string) => {
        this.commitInFlight = false;
        if (this.alive) { this.notice = '本次修改尚未保存到本机，请检查存储空间后点击此处重试。'; }
        // 只记录"这次变更"的重试入口，不留下任何可被再次提交的残留候选。
        if (retry !== undefined && (!preserveExistingRetry || !hadRetry)) {
          this.pendingRetry = this.guardRetry(retry);
        }
        hilog.warn(0x1200, 'YiDa', 'Commit failed: %{public}s', reason);
      },
      onBusy: () => {
        this.commitInFlight = false;
        if (this.alive) { this.toast('正在保存上一项，请稍候'); }
      }
    };
    return this.commitLock.commit(payload, callbacks);
  }

  private guardRetry(action: () => void): () => void {
    const generation: number = this.retryGeneration;
    return () => {
      if (generation === this.retryGeneration) { action(); }
    };
  }

  // 新业务操作开始前清掉旧失败入口，防止旧全量候选覆盖刚改过的状态。
  private invalidateRetry(): void {
    this.retryGeneration++;
    this.pendingRetry = undefined;
  }

  // 顶部提示条的重试入口：明确重试上一次失败的那次变更。
  private retryPersist(): void {
    if (this.readBlocked || !this.repository || this.commitInFlight) { return; }
    const retry: (() => void) | undefined = this.pendingRetry;
    if (retry === undefined) { return; }
    this.pendingRetry = undefined;
    try { retry(); }
    catch (error) {
      if (this.alive) { this.notice = (error as Error).message || '重试失败，请稍后再试'; }
    }
  }

  // 发布之后：应用延后的天气、按需补存、执行被推迟的导航。
  private afterPublish(callback?: () => void): void {
    if (callback !== undefined) { callback(); }
    const mid: number = this.commitLock.takeTemperature();
    if (!Number.isNaN(mid) && mid >= -20 && mid <= 45 && mid !== this.temperature) {
      // 用最新完整状态应用外部变更，再补存一次；旧快照永不进仓储队列。
      this.temperature = mid;
      this.regenerate();
      this.commitLock.requestResave();
    }
    if (this.commitLock.isCardOpenPending()) {
      this.commitLock.takeCardOpen();
      // 卡片唤起在导入流程中也走统一退出保护，不能直接改路由把任务丢下。
      this.handleCardOpen();
    }
    if (this.commitLock.takeResave()) { this.persist(); }
    this.sweepOrphans();
  }

  // 卡片唤起、批量子表单调用的入口：提交进行中就不要中途插入新导航。
  private navigating(): boolean { return this.migrationBusy || this.commitInFlight || this.commitLock.isLocked(); }

  // 所有会改变已发布快照的业务入口共用这道门：提交期间只提示并保留当前输入，
  // 不让调用方先改内存、随后又把一次被拒绝的提交误报成失败重试。
  private businessBusy(): boolean {
    if (!this.navigating()) { return false; }
    this.toast('正在保存上一项，请稍候');
    return true;
  }

  private persist(obsoleteImage: string = ''): void {
    if (this.readBlocked || !this.repository) { return; }
    if (this.navigating()) { this.commitLock.requestResave(); return; }
    const snapshot: DemoSnapshot = this.snapshot();
    const widgetData: CardData = cardData(snapshot);
    // 落盘成功之后才执行这些后续动作：回收旧图、刷新卡片、清理遗留。
    this.commit(snapshot, undefined, () => {
      // 替换图片后只在新快照落盘成功且图片已无人引用时回收旧图。
      if (obsoleteImage.length > 0 && this.repository && this.draft.uri !== obsoleteImage &&
        !this.garments.some((item: Garment) => item.imageUri === obsoleteImage)) {
        this.repository.discardImage(obsoleteImage).catch(() => {
          hilog.warn(0x1200, 'YiDa', 'Replaced image cleanup failed');
        });
      }
      // 直接更新展示数据，不触发 onUpdateForm；后者是鸿蒙 7 摇一摇激活互动卡片的入口。
      this.cardQueue = this.cardQueue.then(async () => {
        const forms = await formProvider.getPublishedRunningFormInfos();
        for (const form of forms) {
          if (form.formName === 'TodayOutfit') { await formProvider.updateForm(form.formId, formBindingData.createFormBindingData(widgetData)); }
        }
      }).catch((error: BusinessError) => {
        hilog.warn(0x1200, 'YiDa', 'Form refresh unavailable: %{public}d %{public}s', error.code, error.message);
      });
    }, () => { this.persist(); }, true);
  }

  private itemsFor(look: Outfit): Garment[] {
    const items: Garment[] = [];
    for (const id of look.garmentIds) {
      const item: Garment | undefined = this.garments.find((entry: Garment) => entry.id === id);
      if (item) { items.push(item); }
    }
    return items;
  }

  private filteredItems(): Garment[] {
    return this.garments.filter((item: Garment) => (this.filterCategory === '全部' || item.category === this.filterCategory) &&
      (this.filterStatus === '全部状态' || item.status === this.filterStatus) &&
      (item.name.indexOf(this.search.trim()) >= 0 || item.color.indexOf(this.search.trim()) >= 0 ||
        (item.subcategory || '').indexOf(this.search.trim()) >= 0 ||
        (item.material || '').indexOf(this.search.trim()) >= 0));
  }

  private changeConditions(): void {
    if (this.businessBusy()) { return; }
    this.invalidateRetry();
    this.regenerate(); this.persist();
  }

  private async shareLook(look: Outfit): Promise<void> {
    try {
      const content: string = '艺起搭 · ' + look.occasion + '穿搭\n' +
        this.itemsFor(look).map((item: Garment) => item.name).join(' + ') + '\n' + look.reason + '\n来自艺起搭';
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT, content: content
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(this.context(), { previewMode: systemShare.SharePreviewMode.DEFAULT });
    } catch (error) { this.toast('未能打开系统分享，请稍后重试'); }
  }

  private replace(look: Outfit, id: string): void {
    if (this.businessBusy()) { return; }
    const result: Recommendation = replaceGarment(look, id, this.garments, this.request());
    if (result.outfits.length === 0) { this.toast(result.explanation); return; }
    this.invalidateRetry();
    const replacement: Outfit = result.outfits[0];
    // 替换可能与另一张推荐卡相同，去重保。ForEach 的标识唯一。
    const updated: Outfit[] = this.plans.map((item: Outfit) => item.id === look.id ? replacement : item);
    this.plans = updated.filter((item: Outfit, index: number) => updated.findIndex((entry: Outfit) => entry.id === item.id) === index);
    this.activeIds = replacement.garmentIds.slice(); this.persist();
  }

  private toggleLock(item: Garment): void {
    if (this.lockedIds.indexOf(item.id) >= 0) {
      this.lockedIds = this.lockedIds.filter((id: string) => id !== item.id);
    } else {
      const sameCategory: string[] = this.garments.filter((entry: Garment) => entry.category === item.category)
        .map((entry: Garment) => entry.id);
      this.lockedIds = this.lockedIds.filter((id: string) => sameCategory.indexOf(id) < 0).concat([item.id]);
      this.excludedIds = this.excludedIds.filter((id: string) => id !== item.id);
    }
    this.regenerate(); this.persist();
  }

  private saveLook(look: Outfit): void {
    if (this.readBlocked || look.garmentIds.length === 0) { this.toast('请先选择可保存的搭配'); return; }
    if (this.businessBusy()) { return; }
    const exists: boolean = this.saved.some((item: Outfit) => item.id === look.id);
    if (!exists && this.saved.length >= 50) { this.toast('收藏已满，请先移除不需要的方案'); return; }
    this.invalidateRetry();
    this.saved = exists ? this.saved.filter((item: Outfit) => item.id !== look.id) : [look].concat(this.saved);
    this.persist(); this.toast(exists ? '已取消收藏' : '已收藏搭配');
  }

  // 。id 改状态：衣橱页的整理入口用它，避免先打开详情再改。
  private setStatusById(id: string, status: GarmentStatus): void {
    if (this.readBlocked || this.businessBusy()) { return; }
    this.invalidateRetry();
    this.garments = this.garments.map((item: Garment) => {
      const changed: Garment = copyGarment(item);
      if (item.id === id) { changed.status = status; }
      return changed;
    });
    this.regenerate(); this.persist();
  }

  private batchEditGarments(ids: string[], status: GarmentStatus | undefined,
    season: string, tag: string): void {
    if (this.readBlocked || this.businessBusy() || ids.length === 0) { return; }
    this.invalidateRetry();
    const selected: string[] = ids.slice();
    const nextGarments: Garment[] = this.garments.map((item: Garment) => {
      if (selected.indexOf(item.id) < 0) { return item; }
      const changed: Garment = copyGarment(item);
      if (status !== undefined) { changed.status = status; }
      if (season.length > 0) { changed.season = season; }
      if (tag.length > 0) {
        const tags: string[] = (changed.tags || []).slice();
        if (tags.indexOf(tag) < 0) { tags.push(tag); }
        changed.tags = tags.slice(0, 12);
      }
      return changed;
    });
    const candidate: DemoSnapshot = this.withGarments(nextGarments);
    this.commit(candidate, () => {
      this.garments = nextGarments;
      this.regenerate();
    }, () => { this.toast(`已批量更新 ${selected.length} 件衣物`); }, () => {
      this.batchEditGarments(selected, status, season, tag);
    });
  }

  private changeStatus(status: GarmentStatus): void {
    if (this.readBlocked || this.businessBusy()) { return; }
    this.invalidateRetry();
    const changed: Garment = copyGarment(this.selectedItem); changed.status = status;
    this.garments = this.garments.map((item: Garment) => item.id === changed.id ? changed : item);
    this.selectedItem = changed; this.regenerate(); this.persist();
  }

  // 单件反馈走全量快照提交：先落盘成功，再刷新当前衣物和推荐，失败时保留顶部重试入口。
  private async setRecommendationBias(bias: number): Promise<void> {
    if (this.readBlocked || this.businessBusy()) { return; }
    const normalized: number = bias > 0 ? 1 : bias < 0 ? -1 : 0;
    const changed: Garment = copyGarment(this.selectedItem);
    changed.recommendationBias = normalized;
    const nextGarments: Garment[] = this.garments.map((item: Garment) =>
      item.id === changed.id ? changed : item);
    this.invalidateRetry();
    await this.commit(this.withGarments(nextGarments), () => {
      this.garments = nextGarments;
      this.selectedItem = changed;
      this.regenerate();
    }, () => {
      this.toast(normalized === 1 ? '已设为优先推荐' : normalized === -1 ? '本轮会少推荐这件' : '已恢复中性推荐');
    }, () => { this.setRecommendationBias(normalized).catch(() => {}); });
  }

  private async pickPhoto(): Promise<void> {
    if (!this.repository || this.importing || this.cuttingOut || this.savingGarment) { return; }
    // 单件编辑也会创建 garment_batch_ 文件；启动遗留清理完成前不能让新文件与清理竞争。
    if (!this.sweepDone) { this.toast('正在整理本机文件，请稍候再选'); return; }
    this.importing = true; this.draft.error = '';
    try {
      const uris: string[] = await this.repository.chooseImages(1);
      const source: string = uris.length > 0 ? uris[0] : '';
      if (!this.alive || !this.showSheet || this.sheet !== 'add') {
        // Picker 只给了会话'URI，没有落盘就无需清理'。
        return;
      }
      if (source.length > 0) {
        // 先导入到沙箱，再替换草稿图片：导入失败时原草稿仍然完整。
        // 每次换图取一个不可复用的文件标识：不能拿草稿数组长度当序号，
        // 否则"取消一次再换一次"会取到同一个值，把上一张还没保存的图片覆盖掉。
        const key: string = this.draftFileKey();
        const uri: string = await this.repository.importImage(source, this.repository.originalPathFor(key));
        if (!this.alive || !this.showSheet || this.sheet !== 'add') {
          await this.repository.discardImage(uri); return;
        }
        this.invalidateRetry();
        this.clearDraft();
        this.draft.uri = uri; this.originalDraftUri = uri; this.draftImages = [uri];
      }
    } catch (error) {
      if (this.alive) { this.draft.error = (error as Error).message || '未能导入图片，请重试'; }
    }
    finally { this.importing = false; }
  }

  // 新增衣物的入口统一进入批量录入页：即使只选一张也走同一套逐件确认流程。
  // 不在这里直接改内存再异步落盘（那样先提示成功、后写盘失败会留下对不上的状态）。
  private openAdd(): void {
    if (this.readBlocked || !this.repository) { return; }
    if (this.navigating()) { this.toast('正在保存上一件，请稍候'); return; }
    const capacity: number = remainingCapacity(this.garments.length);
    if (capacity <= 0) {
      // 满额提示放在打开 Picker 之前，不让用户白选一轮。
      this.toast('衣橱已满 100 件，请先整理后再添加');
      return;
    }
    this.openImport();
  }

  private openImport(): void {
    this.importIndex = 0;
    this.openRoute('garmentImport');
    // 首屏展示系统相册与随包照片两个真实入口，由用户选择本次的图片来源。
  }

  private openEdit(): void {
    if (this.readBlocked) { return; }
    // 每次重新打开编辑都建立新的草稿会话，旧会话的失败重试不能提交新衣物。
    this.invalidateRetry();
    this.clearDraft(); this.editingGarment = true;
    // uri 只保存本轮新选的图片。原图继续由衣物持有，取消编辑时不能删除原图。
    this.draft = { uri: '', name: this.selectedItem.name,
      categoryIndex: CATEGORIES.indexOf(this.selectedItem.category), color: this.selectedItem.color,
      minTemp: this.selectedItem.minTemp, maxTemp: this.selectedItem.maxTemp,
      occasions: this.selectedItem.occasions.slice(), error: '' };
    this.sheet = 'add';
  }

  // ---- 批量录入：队列的唯一所有者。页面只负责显示与回调 ----

  private importCurrent(): ImportItem | undefined {
    if (this.importItems.length === 0) { return undefined; }
    return this.importItems[this.importIndex];
  }

  // ---- 提交链与导入链辅助 ----

  // 打开相册前的容量检查。
  private importCapacity(): number {
    const session: ImportSession | undefined = this.importCtl === undefined
      ? undefined : this.importCtl.currentSession();
    return session === undefined ? remainingCapacity(this.garments.length) : session.capacity(this.garments.length);
  }

  private importCapacityNotice(): string {
    return this.garments.length >= 100 ? '衣橱已满 100 件，请先整理后再添加'
      : '本次最多加入 10 张照片，完成后可再次录入';
  }

  // 单件换图的文件标识：每次调用都取一个不可复用的键。
  // 不能拿草稿数组长度当序号：取消一次再换一次会取到同一个值，覆盖上一张未保存的图片。
  private draftFileKey(): string {
    if (this.importSessionId.length === 0) { this.importSessionId = makeSessionId(Date.now(), 1); }
    return nextDraftFileKey(this.importSessionId);
  }

  private importSessionRef(): ImportSession {
    return this.importController().sessionRef(Date.now(), this.garments.length + 1,
      (items: ImportItem[], index: number) => {
        // 唯一的状态发布通道：页面在这里接收新快照，不维护第二份队列。
        this.importItems = items;
        this.importIndex = index;
        this.maybeHandlePendingImportCard(items);
      });
  }

  // 页面接线集中在这里：导入会话的串行处理与退出清理交给控制器；
  // 全局快照的提交顺序、候选快照和重试仍由本页的 SnapshotCommit 统一协调。
  private importController(): GarmentImportController {
    if (this.importCtl === undefined) {
      this.importCtl = new GarmentImportController(this.importHost());
    }
    return this.importCtl;
  }

  private maybeHandlePendingImportCard(items: ImportItem[]): void {
    if (!this.pendingImportCardOpen || this.importing || this.pendingImportExitScheduled ||
      this.importExitDialogOpen || items.some((item: ImportItem) => isActivePhase(item.phase))) {
      return;
    }
    const current: ImportSession | undefined = this.importCtl === undefined
      ? undefined : this.importCtl.currentSession();
    if (this.pendingImportCardSession !== undefined && current !== this.pendingImportCardSession) {
      // 请求所属会话已经结束，避免后续新会话被旧卡片事件误退出。
      this.pendingImportCardOpen = false;
      this.pendingImportCardSession = undefined;
      return;
    }
    if (this.pendingImportCardSession === undefined && current !== undefined) {
      this.pendingImportCardSession = current;
    }
    // 发布发生在状态机回调内部，延后一轮再打开确认框，避免重入同一次发布。
    this.pendingImportExitScheduled = true;
    const requested: ImportSession | undefined = this.pendingImportCardSession;
    setTimeout(() => {
      this.pendingImportExitScheduled = false;
      const latest: ImportSession | undefined = this.importCtl === undefined
        ? undefined : this.importCtl.currentSession();
      if (!this.alive || !this.pendingImportCardOpen || this.mainRoute !== 'garmentImport' ||
        this.importing || this.importExitDialogOpen || latest !== requested) { return; }
      this.importExit(true);
    }, 0);
  }

  // 图片是否仍被任何持久化记录引用：衣橱、穿搭日记、试穿任务。
  // 少覆盖一处就可能删掉还在用的文件，因此这里是清理前的统一判据。
  private isReferencedImage(uri: string): boolean {
    if (uri.length === 0) { return true; }
    if (this.garments.some((item: Garment) => item.imageUri === uri)) { return true; }
    if (this.diary.some((entry: DiaryEntry) => entry.photoUri === uri)) { return true; }
    return this.tryOnTasks.some((task: TryOnTask) => task.resultUris.indexOf(uri) >= 0);
  }

  // 把仓储与系统能力接进导入链；状态转换不在页面里重复实现。
  private importHost(sampleSource: string = ''): ImportHost {
    return {
      pick: (limit: number) => sampleSource.length > 0 ? Promise.resolve([sampleSource])
        : (this.repository ? this.repository.chooseImages(limit) : Promise.resolve([])),
      copy: (sourceUri: string, taskId: string) => {
        if (!this.repository) { return Promise.reject(new Error('仓储尚未就绪')); }
        const sampleId: string = bundledPhotoId(sourceUri);
        const target: string = this.repository.originalPathFor(taskId);
        return sampleId.length > 0
          ? importBundledGarmentPhoto(this.context(), sampleId, target)
          : this.repository.importImage(sourceUri, target);
      },
      cutout: (originalUri: string, taskId: string) => {
        if (!cutoutSupported()) { return Promise.reject(new Error('当前设备不支持主体抠图，可继续使用原图')); }
        if (cutoutInFlight()) { return Promise.reject(new Error('已有一个抠图任务在进行，请等它结束再试')); }
        if (!this.repository) { return Promise.reject(new Error('仓储尚未就绪')); }
        return cutoutGarment(originalUri, this.repository.cutoutPathFor(taskId));
      },
      discard: (uri: string) => this.repository ? this.repository.discardImage(uri) : Promise.resolve(),
      isReferenced: (uri: string) => this.isReferencedImage(uri),
      isAlive: () => this.alive && this.mainRoute === 'garmentImport'
    };
  }

  // 提交成功的统一后续：先标记服务内任务 SAVED（taskId），再回收未选用的版本。
  // 衣橱侧的更新（garmentId）由控制器的 publish 回调完成。
  private publishImportItem(session: ImportSession, taskId: string, garmentId: string, usedImage: string): void {
    // 先标记 SAVED，再允许退出清理：dispose 会跳过已保存项。
    session.markSaved({ taskId: taskId, garmentId: garmentId });
    const item: ImportItem | undefined = session.find(taskId);
    if (item !== undefined) { session.releaseUnused(item, usedImage, this.importHost()); }
    this.regenerate();
    this.refreshCard();
  }

  // 选图：校验容量后交给生产导入链（service/GarmentImportRunner.ets）；
  // 取消时返回 0，不生成空衣物、不显示失败。
  private async pickImportPhotos(): Promise<void> {
    if (!this.repository || this.mainRoute !== 'garmentImport') { return; }
    if (this.importCapacity() <= 0) { this.toast(this.importCapacityNotice()); return; }
    // 启动遗留清理结束前不建立新文件：否则新文件可能被当成遗留文件删掉。
    if (!this.sweepDone) { this.toast('正在整理本机文件，请稍候再选'); return; }
    if (this.importing || this.navigating()) { return; }
    this.importing = true;
    try {
      const session: ImportSession = this.importSessionRef();
      const created: number = await session.pick(this.importHost(), this.garments.length);
      if (created > 0) {
        // 选中新任务后，之前失败的全量快照重试入口不再对应当前用户操作。
        this.invalidateRetry();
        this.toast('已选择 ' + created + ' 张，逐件确认后保存');
      }
    } catch (error) {
      this.toast('未能打开相册，请稍后重试');
    } finally {
      this.importing = false;
      // 卡片请求在 Picker 期间只登记不处理；取消和选图结束后都从同一出口继续。
      if (this.pendingImportCardOpen) { this.maybeHandlePendingImportCard(this.importItems); }
    }
  }

  // 随包照片只作为本次会话的来源标识；复制成功后仍由同一任务持有独立 PNG，
  // 保存、重试和退出清理与系统相册选中的照片完全一致。
  private async pickImportSample(id: string): Promise<void> {
    if (!this.repository || this.mainRoute !== 'garmentImport') { return; }
    if (this.importCapacity() <= 0) { this.toast(this.importCapacityNotice()); return; }
    if (!this.sweepDone) { this.toast('正在整理本机文件，请稍候再选'); return; }
    if (this.importing || this.navigating()) { return; }
    this.importing = true;
    try {
      const source: string = bundledPhotoSource(id);
      if (source.length === 0) { throw new Error('未知示例照片'); }
      const session: ImportSession = this.importSessionRef();
      const created: number = await session.pick(this.importHost(source), this.garments.length);
      if (created > 0) {
        this.invalidateRetry();
        this.toast('已加入示例照片');
      }
    } catch (error) {
      this.toast('示例照片未能导入，请重试');
    } finally {
      this.importing = false;
      if (this.pendingImportCardOpen) { this.maybeHandlePendingImportCard(this.importItems); }
    }
  }

  // 页面只调用会话；快照由会话通过 subscribe 发布，不在这里手工同步。
  private importMove(index: number): void {
    if (this.navigating()) { return; }
    this.importSessionRef().select(index);
  }

  private importName(index: number, value: string): void {
    if (this.navigating()) { return; }
    this.invalidateRetry();
    this.importApply(index, 'name', value);
  }

  private importColor(index: number, value: string): void {
    if (this.navigating()) { return; }
    this.invalidateRetry();
    this.importApply(index, 'color', value);
  }

  private importSubcategory(index: number, value: string): void {
    if (this.navigating()) { return; }
    this.invalidateRetry();
    this.importApply(index, 'subcategory', value);
  }

  private importMaterial(index: number, value: string): void {
    if (this.navigating()) { return; }
    this.invalidateRetry();
    this.importApply(index, 'material', value);
  }

  private importOccasions(index: number, occasions: string[]): void {
    if (this.navigating()) { return; }
    this.invalidateRetry();
    this.importApply(index, 'occasions', occasions);
  }

  private importCategory(index: number, categoryIndex: number): void {
    if (this.navigating()) { return; }
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined) { return; }
    this.invalidateRetry();
    const id: string = item.id;
    this.importSessionRef().edit(id, (items: ImportItem[]) => applyCategory(items, id, categoryIndex));
  }

  private importMinTemp(index: number, value: number): void {
    if (this.navigating()) { return; }
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined) { return; }
    this.invalidateRetry();
    const id: string = item.id;
    this.importSessionRef().edit(id, (items: ImportItem[]) => applyMinTemp(items, id, value));
  }

  private importMaxTemp(index: number, value: number): void {
    if (this.navigating()) { return; }
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined) { return; }
    this.invalidateRetry();
    const id: string = item.id;
    this.importSessionRef().edit(id, (items: ImportItem[]) => applyMaxTemp(items, id, value));
  }

  // 文本类字段按字段名改草稿；没有任何字段变化时不重新赋值，避免无效刷新打断滑杆。
  private importApply(index: number, field: string, value: string | string[]): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined) { return; }
    const id: string = item.id;
    this.importSessionRef().edit(id, (items: ImportItem[]) => {
      if (field === 'name' && typeof value === 'string') {
        return applyDraft(items, id, { name: value });
      }
      if (field === 'color' && typeof value === 'string') {
        return applyDraft(items, id, { color: value });
      }
      if (field === 'subcategory' && typeof value === 'string') {
        return applyDraft(items, id, { subcategory: value });
      }
      if (field === 'material' && typeof value === 'string') {
        return applyDraft(items, id, { material: value });
      }
      if (field === 'occasions' && Array.isArray(value)) {
        return applyDraft(items, id, { occasions: value as string[] });
      }
      return items;
    });
  }

  private importRecognitionHint(): ImportRecognitionHint | undefined {
    const item: ImportItem | undefined = this.importItems[this.importIndex];
    if (item === undefined) { return undefined; }
    return this.importRecognitionHints.find((hint: ImportRecognitionHint) =>
      hint.taskId === item.id && hint.revision === item.revision && hint.originalUri === item.originalUri);
  }

  // 只对已复制到本机的原图分析像素并运行端侧模型。异步结束后按会话、taskId 和图片 URI 核对，
  // 防止用户切项、跳过或重新复制时，旧建议写到另一件衣物上。
  private async recognizeImportColor(index: number): Promise<void> {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || item.originalUri.length === 0 || this.recognizingImportTaskId.length > 0 ||
      this.navigating() || this.readBlocked || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED || isActivePhase(item.phase)) { return; }
    const session: ImportSession = this.importSessionRef();
    const taskId: string = item.id;
    const originalUri: string = item.originalUri;
    const revision: number = item.revision;
    this.recognizingImportTaskId = taskId;
    try {
      const result: GarmentRecognition = await recognizeGarment(originalUri);
      let candidate: ClothingCandidate | undefined = undefined;
      try { candidate = await garmentModel.classify(originalUri, this.context()); }
      catch (_) { /* 模型或设备能力不可用时，主色与手填流程继续可用。 */ }
      const current: ImportItem | undefined = session.find(taskId);
      if (!this.alive || this.mainRoute !== 'garmentImport' || this.importCtl === undefined ||
        this.importCtl.currentSession() !== session || current === undefined ||
        current.originalUri !== originalUri || current.revision !== revision || current.phase === ImportPhase.SAVED ||
        current.phase === ImportPhase.SKIPPED) { return; }
      const usable: boolean = result.colorSource === RECOGNITION_SOURCE_PIXEL_COLOR && result.color.length > 0;
      // 模型是通用多标签分类器，只给少数可映射到衣橱的品类候选；用户自行确认。
      const categoryIndex: number = candidate === undefined ? -1 : CATEGORIES.indexOf(candidate.category);
      let message: string = recognitionSummary(result);
      if (candidate !== undefined) {
        const candidateMessage: string =
          `端侧模型候选：${candidate.subcategory}（${candidate.label}，模型分 ${Math.round(candidate.score * 100)}%，请核对）。`;
        // 没有像素主色时，recognitionSummary 会返回“暂无建议”。此时已有
        // 模型候选，应直接展示候选，避免用户同时看到互相矛盾的两句话。
        message = message.indexOf('暂无可用建议') >= 0 ? candidateMessage : `${message} ${candidateMessage}`;
      }
      const hint: ImportRecognitionHint = { taskId: taskId, revision: revision, originalUri: originalUri,
        color: usable ? result.color : '', categoryIndex: categoryIndex,
        subcategory: candidate === undefined ? '' : candidate.subcategory, message: message };
      this.importRecognitionHints = this.importRecognitionHints.filter((entry: ImportRecognitionHint) =>
        entry.taskId !== taskId).concat([hint]);
    } catch (error) {
      const current: ImportItem | undefined = session.find(taskId);
      if (this.alive && this.mainRoute === 'garmentImport' && this.importCtl?.currentSession() === session && current !== undefined &&
        current.originalUri === originalUri && current.revision === revision &&
        current.phase !== ImportPhase.SAVED && current.phase !== ImportPhase.SKIPPED) {
          this.importRecognitionHints = this.importRecognitionHints.filter((entry: ImportRecognitionHint) =>
            entry.taskId !== taskId).concat([{ taskId: taskId, revision: revision, originalUri: originalUri,
              color: '', categoryIndex: -1, subcategory: '', message: '图片分析未完成，请手动填写' }]);
      }
    } finally {
      if (this.recognizingImportTaskId === taskId) { this.recognizingImportTaskId = ''; }
    }
  }

  private useRecognizedColor(index: number): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || isActivePhase(item.phase) || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED) { return; }
    const hint: ImportRecognitionHint | undefined = this.importRecognitionHints.find((entry: ImportRecognitionHint) =>
      entry.taskId === item.id && entry.revision === item.revision && entry.originalUri === item.originalUri);
    if (hint === undefined || hint.color.length === 0) { return; }
    this.importColor(index, hint.color);
  }

  private useRecognizedCategory(index: number): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || isActivePhase(item.phase) || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED) { return; }
    const hint: ImportRecognitionHint | undefined = this.importRecognitionHints.find((entry: ImportRecognitionHint) =>
      entry.taskId === item.id && entry.revision === item.revision && entry.originalUri === item.originalUri);
    if (hint === undefined || hint.categoryIndex < 0 || hint.subcategory.length === 0) { return; }
    this.importCategory(index, hint.categoryIndex);
    this.importSubcategory(index, hint.subcategory);
  }

  // 原图/抠图切换只作用于当前项，不动其它任务。
  private importUseOriginal(index: number): void {
    if (this.navigating()) { return; }
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined) { return; }
    this.invalidateRetry();
    this.importSessionRef().useCutout(item.id, false);
  }

  private importCutout(index: number): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || !this.repository || this.readBlocked || this.navigating()) { return; }
    this.invalidateRetry();
    // 已有抠图结果无需再次调用原生能力，直接切换当前展示/保存版本。
    if (item.cutoutUri.length > 0) {
      this.importSessionRef().useCutout(item.id, true);
      return;
    }
    this.importSessionRef().runCutout(this.importHost(), item.id);
  }

  // 重试严格按 failureStep 分派：COPY/CUTOUT 回到串行队列，SAVE 重新提交。
  private importRetry(index: number): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || this.navigating()) { return; }
    if (item.failureStep === ImportFailureStep.SAVE) {
      this.importConfirm(index);
      return;
    }
    if (item.failureStep === ImportFailureStep.COPY || item.failureStep === ImportFailureStep.CUTOUT) {
      this.invalidateRetry();
      this.importSessionRef().retry(this.importHost(), item.id);
      return;
    }
    if (item.phase === ImportPhase.ERROR) { this.importConfirm(index); }
  }

  // 逐件保存：校验与容量 → 提交锁 → 落盘成功后才移交图片所有权并增加已保存数。
  private async importConfirm(index: number): Promise<void> {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || !this.repository) { return; }
    if (this.readBlocked) { this.toast('本地数据不可写，请先恢复存储'); return; }
    if (this.navigating() || isActivePhase(item.phase)) { return; }
    this.invalidateRetry();
    const session: ImportSession = this.importSessionRef();
    const taskId: string = item.id;
    const reason: string = canSave(item, this.garments.length);
    if (reason.length > 0) { this.toast(reason); return; }
    // 提交前再核对一次容量，不靠打开 Picker 时的那次检查。
    if (remainingCapacity(this.garments.length) <= 0) {
      session.edit(taskId,
        (items: ImportItem[]) => saveFailed(items, taskId, '衣橱已满 100 件，请先整理后再保存'));
      return;
    }
    const candidate: Garment = {
      id: item.garmentId, name: item.draft.name.trim(), category: CATEGORIES[item.draft.categoryIndex],
      subcategory: (item.draft.subcategory || '').trim(), material: (item.draft.material || '').trim(),
      imageKey: '', imageUri: activeImportImage(item), color: item.draft.color,
      minTemp: item.draft.minTemp, maxTemp: item.draft.maxTemp, occasions: item.draft.occasions.slice(),
      // 用户仍要确认全部属性；来源于安装包的照片继续标为示例，不冒充用户自己的衣物。
      status: GarmentStatus.READY, wearCount: 0, isDemo: bundledPhotoId(item.sourceUri).length > 0,
      // 导入衣物在用户确认前保持中性偏好属性，不猜版型和风格。
      fit: '合身', palette: '基础色', style: '简约', layering: false, pattern: false
    };
    // 幂等：同一 garmentId 已经在衣橱里就算已保存，不追加第二件。
    const exists: boolean = this.garments.some((entry: Garment) => entry.id === candidate.id);
    const nextGarments: Garment[] = exists
      ? this.garments.map((entry: Garment) => entry.id === candidate.id ? candidate : entry)
      : this.garments.concat([candidate]);
    // 候选快照在本次操作里局部构造，提交成功才发布；失败不留下任何残留候选。
    const candidateSnapshot: DemoSnapshot = this.withGarments(nextGarments);
    session.beginSave(taskId);
    const saved: boolean = await this.commit(candidateSnapshot, () => {
      // 发布：衣橱更新（garmentId 对应的候选）+ 任务标记 SAVED（taskId）。
      this.garments = nextGarments;
      this.publishImportItem(session, taskId, candidate.id, candidate.imageUri);
    }, () => {
      this.toast('已保存这件衣物');
    }, () => {
      // 重试必须确认仍是同一个会话与任务；退出后同一个 index 可能已经指向另一张图片。
      const current: ImportSession | undefined = this.importCtl === undefined
        ? undefined : this.importCtl.currentSession();
      if (!this.alive || this.mainRoute !== 'garmentImport' || current !== session) { return; }
      const retryIndex: number = session.items.findIndex((entry: ImportItem) => entry.id === taskId);
      if (retryIndex >= 0) { this.importConfirm(retryIndex); }
    });
    if (!saved) {
      // 失败时保持当前项与全部输入图片，草稿可原样重试。
      session.edit(taskId,
        (items: ImportItem[]) => saveFailed(items, taskId, '保存失败：请检查存储空间后重试'));
    }
  }

  private refreshCard(): void {
    const data: CardData = cardData(this.snapshot());
    this.cardQueue = this.cardQueue.then(async () => {
      const forms = await formProvider.getPublishedRunningFormInfos();
      for (const form of forms) {
        if (form.formName === 'TodayOutfit') { await formProvider.updateForm(form.formId, formBindingData.createFormBindingData(data)); }
      }
    }).catch((error: BusinessError) => {
      hilog.warn(0x1200, 'YiDa', 'Form refresh unavailable: %{public}d %{public}s', error.code, error.message);
    });
  }

  // 放弃当前项：改了字段或有处理结果时先确认；在途任务先失效，落地后再补清理。
  private importSkip(index: number): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || this.navigating() || item.phase === ImportPhase.SAVED ||
      item.phase === ImportPhase.SKIPPED) { return; }
    if (needsSkipConfirm(item)) {
      this.getUIContext().getPromptAction().showDialog({ title: '放弃这一件？',
        message: '这一件还没有保存，已填写的内容和这张照片都不会保留。其他项不受影响',
        buttons: [{ text: '继续编辑', color: $r('app.color.text_secondary') },
          { text: '放弃', color: $r('app.color.warning') }]
      }).then((result) => {
        if (result.index === 1) { this.dropImportItem(index); }
      }).catch(() => {});
      return;
    }
    this.dropImportItem(index);
  }

  private dropImportItem(index: number): void {
    const item: ImportItem | undefined = this.importItems[index];
    if (item === undefined || this.businessBusy()) { return; }
    this.invalidateRetry();
    // 会话负责让在途结果失效（revision 自增）并清理文件；真正返回的回调只做清理。
    this.importSessionRef().skip(this.importHost(), item.id);
  }

  // 只清理发起这次对话框时所属会话的卡片请求，避免旧回调误清理新会话。
  private clearPendingImportCard(requestedSession: ImportSession | undefined): void {
    const current: ImportSession | undefined = this.importCtl === undefined
      ? undefined : this.importCtl.currentSession();
    if (current !== requestedSession || this.pendingImportCardSession !== requestedSession) { return; }
    this.pendingImportCardOpen = false;
    this.pendingImportCardSession = undefined;
  }

  private isCurrentImportExit(requestedSession: ImportSession | undefined): boolean {
    const current: ImportSession | undefined = this.importCtl === undefined
      ? undefined : this.importCtl.currentSession();
    return this.alive && this.mainRoute === 'garmentImport' && current === requestedSession;
  }

  // 离开流程：有未完成项时确认放弃；已保存项保留；没有未完成项直接返回。
  // cardOpen=true 表示这是卡片唤起触发的退出，确认后回到今日而不是简单返回。
  private importExit(cardOpen: boolean = false): void {
    if (this.navigating() || this.importing || this.importExitDialogOpen) {
      if (this.navigating()) { this.toast('正在保存，请稍候'); }
      return;
    }
    if (this.importItems.some((item: ImportItem) => isActivePhase(item.phase))) {
      this.toast('还有图片在处理中，请稍候再退出');
      return;
    }
    const pending: ImportItem[] = this.importItems.filter((item: ImportItem) => isPending(item));
    if (pending.length === 0) { this.finishImport(cardOpen); return; }
    const requestedSession: ImportSession | undefined = this.importCtl === undefined
      ? undefined : this.importCtl.currentSession();
    this.importExitDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({ title: '结束本次录入？',
      message: `还有 ${pending.length} 件没有保存。已经保存的 ${summaryOf(this.importItems).saved} 件会保留，未保存的输入会被丢弃。`,
      buttons: [{ text: '继续录入', color: $r('app.color.text_secondary') },
        { text: '结束', color: $r('app.color.warning') }]
    }).then((result) => {
      this.importExitDialogOpen = false;
      const current: ImportSession | undefined = this.importCtl === undefined
        ? undefined : this.importCtl.currentSession();
      const sameSession: boolean = current === requestedSession;
      if (result.index !== 1) {
        // 普通返回期间也可能收到卡片事件；取消时清掉当前会话的延后请求，
        // 但不让旧会话的异步回调碰到新会话。
        if (this.isCurrentImportExit(requestedSession)) {
          this.clearPendingImportCard(requestedSession);
        }
        return;
      }
      // 对话框是异步回调：确认时再次核对页面存活、路由和会话，
      // 防止旧对话框结束后关闭新会话或把卡片请求带到下一轮导入。
      if (!this.isCurrentImportExit(requestedSession) || !sameSession) {
        return;
      }
      // 会话已经释放完，此时再走统一路由动画，不会丢下未完成的任务。
      this.finishImport(cardOpen || this.pendingImportCardOpen);
    }).catch(() => {
      this.importExitDialogOpen = false;
      this.pendingImportCardOpen = false;
      this.pendingImportCardSession = undefined;
    });
  }

  private finishImport(cardOpen: boolean = false): void {
    // 未保存项由控制器统一失效并清理；已保存项引用的图片受引用保护。
    this.pendingImportCardOpen = false;
    this.pendingImportCardSession = undefined;
    this.pendingImportExitScheduled = false;
    this.importExitDialogOpen = false;
    this.invalidateRetry();
    const saved: number = this.importController().exit();
    this.importRecognitionHints = [];
    this.importItems = [];
    this.importIndex = 0;
    if (saved > 0) {
      this.toast('已保存 ' + saved + ' 件衣物');
    }
    if (cardOpen) {
      this.pendingImportCardOpen = false;
      // 卡片直达回今日也经过现有 240ms 路由动画，不能用直接赋值中断过渡。
      this.returnToToday();
    } else {
      // 普通返回仍走原来的关闭动画方法，不直接改 mainRoute。
      this.closeRoute();
      if (saved > 0) {
        this.switchTab(1);
      }
    }
  }

  // ---- 新页面路由与回调：首页、搭配DIY、穿搭日记、AI 试穿共用本页的状态与仓储 ----

  private openRoute(route: string): void {
    if (route === this.mainRoute) { return; }
    this.routeHistory.push(this.mainRoute);
    // 状态变更必须包。animateTo 里，挂在容器上的 transition 才会真的播；
    // 直接赋值只会瞬切，transition 不生效。
    animateTo({ duration: 280, curve: Curve.FastOutSlowIn }, () => { this.mainRoute = route; });
  }

  // 切页签统一走这里。
  // 直接。this.tab = 1 不会播过渡——首页里的「衣橱整理」「今日搭配」等入口原先都是直接赋值，
  // 所以点了没动画。全部收口到一个方法，避免以后再漏。
  //
  // 注意：HdsTabs 。animationDuration 只作用于"用户点页。/ 滑动"。
  // 程序化改 index 不走那套动画（实测把时长调到 2 秒仍是瞬切）。
  // 所以这里自己做一。先退场、再切换、后进场"。
  private switchTab(index: number): void {
    if (index === this.tab) { return; }
    animateTo({ duration: 130, curve: Curve.FastOutSlowIn }, () => { this.tabPhase = 0; });
    setTimeout(() => {
      this.tab = index;
      animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => { this.tabPhase = 1; });
    }, 140);
  }

  private closeRoute(): void {
    if (this.mainRoute === 'tryOn') {
      this.tryOnCommand = { id: 0, action: 'start', sceneId: this.tryOnSceneId };
    }
    animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => {
      this.mainRoute = this.routeHistory.pop() || 'tabs';
    });
    this.regenerate();
  }

  onBackPress(): boolean {
    if (this.showSheet) { this.showSheet = false; return true; }
    // 批量录入的返回（顶部返回键与系统返回键）走同一个出口：
    // 有未完成项时先确认，已保存项保留，没有未完成项直接返回。保存期间不允许离开。
    if (this.mainRoute === 'garmentImport') { this.importExit(); return true; }
    if (this.mainRoute !== 'tabs') { this.closeRoute(); return true; }
    return false;
  }

  private openTile(name: string): void {
    if (name === '穿搭测评') { this.openQuiz(); }
    else if (name === '添加衣物') { this.openAdd(); }
    else if (name === '今日搭配') { this.switchTab(2); this.showSaved = false; }
    else if (name === '搭配收藏') { this.switchTab(2); this.showSaved = true; }
    else if (name === '衣橱整理') { this.switchTab(1); }
    else if (name === '桌面卡片') { this.openCardManager(); }
  }

  // 领取 7 天会员体验：只记录真实存在的体验期，不承诺无法核销的权益。
  private claimTrial(): void {
    if (trialDaysLeft(this.membership) > 0) { this.toast('体验已在使用'); return; }
    if (this.businessBusy()) { return; }
    this.invalidateRetry();
    this.membership = { startDate: new Date().toISOString(), trialDays: 7,
      tryOnUsed: this.membership.tryOnUsed };
    this.persist(); this.toast('已领。7 天体验，基础功能一直可');
  }

  // 本月有穿搭记录的天数（日记与穿着记录合并去重），用于首页横幅文案。
  private monthRecordedDays(): number {
    const prefix: string = localDay().slice(0, 7) + '-';
    return recordedDays(this.diary, this.records).filter((day: string) => day.startsWith(prefix)).length;
  }

  private cityName(): string { return this.city.length > 0 ? this.city : '未选择城市'; }

  // 应用城市与温度：温度直接决定推荐候选，所以两者一起提交。
  private async applyCity(city: CityOption, temperature: number): Promise<void> {
    if (this.readBlocked || !this.repository) { this.toast('本地数据不可写，请先恢复衣橱'); return; }
    if (this.businessBusy() || !Number.isFinite(temperature) || temperature < -20 || temperature > 45) { return; }
    this.invalidateRetry();
    // 手动切城后，先前发起的天气请求不能再覆盖用户选择。
    this.weatherRequest += 1;
    const nextRequest: OutfitRequest = this.request();
    nextRequest.temperature = temperature;
    const preview: Recommendation = recommend(this.garments, nextRequest);
    const nextActiveIds: string[] = preview.outfits.length > 0 ? preview.outfits[0].garmentIds.slice() : [];
    const base: DemoSnapshot = this.snapshot();
    const candidate: DemoSnapshot = { version: base.version, garments: base.garments, saved: base.saved,
      records: base.records, occasion: base.occasion, temperature: temperature, activeIds: nextActiveIds,
      profile: base.profile, diary: base.diary, tryOnTasks: base.tryOnTasks,
      membership: base.membership, body: base.body, city: city.name };
    await this.commit(candidate, () => {
      this.city = city.name;
      this.temperature = temperature;
      this.activeIds = nextActiveIds;
      WeatherService.setManualCity(city);
      // 手动切城后清掉旧城市的实测天气，避免把旧数据标到新城市名下。
      this.weather = { available: false, city: city.name, condition: '', tempMin: 0,
        tempMax: 0, source: '手动温度' };
      this.regenerate();
    }, () => {
      this.showSheet = false;
      this.refreshCard();
      this.toast('已切换到' + city.name);
    }, () => { this.applyCity(city, temperature).catch(() => {}); });
  }

  private async saveBodyProfile(next: BodyProfile): Promise<void> {
    if (this.readBlocked || !this.repository) { throw new Error('本地数据不可写'); }
    if (this.businessBusy()) { throw new Error('正在保存上一项，请稍候'); }
    this.invalidateRetry();
    const nextRequest: OutfitRequest = this.request();
    nextRequest.body = next;
    const preview: Recommendation = recommend(this.garments, nextRequest);
    const nextActiveIds: string[] = preview.outfits.length > 0 ? preview.outfits[0].garmentIds.slice() : [];
    const candidate: DemoSnapshot = this.withBody(next, nextActiveIds);
    const saved: boolean = await this.commit(candidate, () => {
      this.body = next;
      this.activeIds = nextActiveIds;
      this.regenerate();
    }, () => {
      this.showSheet = false;
      this.refreshCard();
      this.toast('档案已保存，推荐已更新');
    }, () => { this.saveBodyProfile(next).catch(() => {}); });
    if (!saved) { throw new Error('档案尚未保存到本机，请检查存储空间后重试'); }
  }

  // DIY 与详情里保存方案：同一 id 视为更新，避免重复堆叠。
  // 先落盘、再发布：失败时把收藏列表恢复成改动前的样子。
  private async upsertOutfit(look: Outfit): Promise<void> {
    if (this.readBlocked || !this.repository) { throw new Error('本地数据不可写'); }
    if (this.businessBusy()) { throw new Error('正在保存上一项，请稍候'); }
    // 新的 DIY 提交取代旧失败候选；重试回调会在本次失败后重新登记。
    this.invalidateRetry();
    const exists: boolean = this.saved.some((item: Outfit) => item.id === look.id);
    // 容量限制不能通过裁掉旧作品实现；达到上限仍允许编辑已有作品。
    if (!exists && this.saved.length >= 50) { throw new Error('收藏已满，请先移除不需要的方案'); }
    const nextSaved: Outfit[] = exists ? this.saved.map((item: Outfit) => item.id === look.id ? look : item)
      : [look].concat(this.saved);
    // 候选快照必须包含 nextSaved：否则落盘的收藏还是旧的，内存却已经改了。
    const candidate: DemoSnapshot = this.withSaved(nextSaved);
    const saved: boolean = await this.commit(candidate, () => {
      this.saved = nextSaved;
    }, () => {
      this.toast(exists ? '已更新方案' : '已保存方案');
    }, () => { this.upsertOutfit(look).catch(() => {}); });
    if (!saved) {
      this.notice = '方案尚未保存到本机，请重试';
      throw new Error('方案保存失败');
    }
  }

  private openStudio(look?: Outfit): void {
    if (look) { this.studioDraft = look; }
    this.openRoute('outfitStudio');
  }

  private openOutfitDetail(look: Outfit): void { this.selectedLook = look; this.openRoute('outfitDetail'); }

  private openTryOn(sceneId: string = 'denim_skirt'): void {
    // 入口可能来自旧快照或 Profile 历史记录，未知场景统一回落到第一组合法样片。
    this.tryOnSceneId = findDemoScene(sceneId) !== undefined ? sceneId : 'denim_skirt';
    this.openRoute('tryOn');
  }

  private beginWear(look: Outfit): void {
    if (this.readBlocked) { this.toast('本地数据不可写，请先恢复存储'); return; }
    if (look.garmentIds.length === 0) { this.toast('请先选择一套搭'); return; }
    this.pendingWearId = 'wear_' + Date.now();
    this.selectedLook = look; this.openSheet('feedback');
  }

  private recordToday(): void {
    if (this.todayRecorded()) { this.openRoute('diary'); return; }
    const look: Outfit | undefined = this.plans.find((item: Outfit) =>
      item.garmentIds.join(',') === this.activeIds.join(',')) || this.plans[0];
    if (look === undefined) { this.switchTab(2); this.toast(this.explanation || '请先添加可穿衣物'); return; }
    this.beginWear(look);
  }

  private async commitDiary(changeFactory: () => DiaryMutation): Promise<void> {
    if (this.readBlocked || !this.repository) { throw new Error('本地数据不可写'); }
    if (this.businessBusy()) { throw new Error('正在保存上一项，请稍候'); }
    // 每次日记操作都基于当前已发布状态重新计算，旧失败候选不能覆盖新的记录。
    this.invalidateRetry();
    const change: DiaryMutation = changeFactory();
    if (change.error.length > 0) { throw new Error(change.error); }
    // 候选快照在本次操作里局部构造；落盘成功才发布到内存。
    const candidate: DemoSnapshot = this.withDiary(change);

    const saved: boolean = await this.commit(candidate, () => {
      this.diary = change.diary; this.records = change.records; this.garments = change.garments;
      this.regenerate();
    }, undefined, () => { this.commitDiary(changeFactory).catch(() => {}); });
    if (!saved) {
      this.notice = '穿搭记录尚未保存，请重试';
      throw new Error('保存失败，当前内容仍在，请重试');
    }
  }

  private async addDiaryEntry(entry: DiaryEntry): Promise<void> {
    await this.commitDiary(() => saveDiary(this.diary, this.records, this.garments, entry));
    this.toast('已保存穿搭日记');
  }

  private async deleteDiaryEntry(id: string): Promise<void> {
    const target: DiaryEntry | undefined = this.diary.find((item: DiaryEntry) => item.id === id);
    await this.commitDiary(() => removeDiary(this.diary, this.records, this.garments, id));
    // 等删除快照成功落盘再回收照片，失败重启时原快照仍能读到图片。
    if (target && target.photoUri.length > 0 && this.repository &&
      !this.diary.some((entry: DiaryEntry) => entry.photoUri === target.photoUri)) {
      this.repository.discardImage(target.photoUri).catch(() => {});
    }
    this.toast('已删除这条记');
  }

  // 试穿页面只提交固定场景 ID；任务由本页依据当前已发布快照创建，避免 UI 传入伪造任务。
  // 先把候选快照落盘，提交成功后再发布 tryOnTasks，失败时保留原状态并交给顶部重试入口。
  private async submitTryOn(sceneId: string): Promise<void> {
    if (this.readBlocked || !this.repository) { throw new Error('本地数据不可写'); }
    if (this.businessBusy()) { throw new Error('正在保存上一项，请稍候'); }
    this.invalidateRetry();
    const nextTasks: TryOnTask[] = saveDemoTask(this.tryOnTasks, sceneId);
    // 相同场景再次提交是幂等操作，不重复写入，也不因已满容量误报失败。
    if (nextTasks.length === this.tryOnTasks.length) {
      this.toast('这组试穿样片已在记录中');
      return;
    }
    const candidate: DemoSnapshot = this.withTryOnTasks(nextTasks);
    const saved: boolean = await this.commit(candidate, () => {
      this.tryOnTasks = nextTasks;
    }, () => {
      this.toast('已记录试穿样片');
    }, () => { this.submitTryOn(sceneId).catch(() => {}); });
    if (!saved) {
      this.notice = '试穿样片尚未保存，请重试';
      throw new Error('试穿样片保存失败');
    }
  }

  // 删除同样走候选快照提交，磁盘失败时不会先从页面状态中移除记录。
  private async deleteTryOnTask(id: string): Promise<void> {
    if (this.readBlocked || !this.repository) { throw new Error('本地数据不可写'); }
    if (this.businessBusy()) { throw new Error('正在保存上一项，请稍候'); }
    const exists: boolean = this.tryOnTasks.some((item: TryOnTask) => item.id === id);
    if (!exists) { return; }
    this.invalidateRetry();
    const nextTasks: TryOnTask[] = this.tryOnTasks.filter((item: TryOnTask) => item.id !== id);
    const candidate: DemoSnapshot = this.withTryOnTasks(nextTasks);
    const saved: boolean = await this.commit(candidate, () => {
      this.tryOnTasks = nextTasks;
    }, () => {
      this.toast('已删除试穿样片');
    }, () => { this.deleteTryOnTask(id).catch(() => {}); });
    if (!saved) {
      this.notice = '试穿样片删除尚未保存，请重试';
      throw new Error('试穿样片删除失败');
    }
  }

  private todayRecorded(): boolean {
    return recordedDays(this.diary, this.records).indexOf(localDay()) >= 0;
  }

  // 单件表单（仅编辑已有衣物）的保存。
  // 新增走批量录入页；这里保留编辑能力，并且与批量流程共用同一套提交锁。
  // 先落盘成功，再关弹层、交图片所有权，失败时草稿与原图都留着。
  private async addGarment(): Promise<void> {
    if (this.readBlocked || !this.repository || this.savingGarment) { return; }
    if (this.navigating()) { this.toast('正在保存，请稍候'); return; }
    this.invalidateRetry();
    if (this.draft.name.trim().length === 0 || this.draft.occasions.length === 0 ||
      this.draft.minTemp > this.draft.maxTemp || this.draft.categoryIndex < 0) {
      this.draft.error = '请填写名称与场合，选择品类，并确认最低温度不高于最高温度'; return;
    }
    if (!this.editingGarment) { return; }
    const changed: Garment = copyGarment(this.selectedItem);
    const obsoleteImage: string = this.draft.uri.length > 0 ? changed.imageUri : '';
    changed.name = this.draft.name.trim(); changed.category = CATEGORIES[this.draft.categoryIndex];
    if (changed.category !== this.selectedItem.category) { changed.subcategory = ''; }
    changed.color = this.draft.color; changed.minTemp = this.draft.minTemp; changed.maxTemp = this.draft.maxTemp;
    changed.occasions = this.draft.occasions.slice();
    if (this.draft.uri.length > 0) {
      changed.imageUri = this.draft.uri; changed.imageKey = ''; changed.isDemo = false;
    }
    const nextGarments: Garment[] = this.garments.map((item: Garment) => item.id === changed.id ? changed : item);
    // 候选快照在本次操作里局部构造，提交成功才发布。
    const candidate: DemoSnapshot = this.withGarments(nextGarments);
    // 重试必须绑定本次编辑的衣物和草稿对象；同一会话内继续修改仍可正常重试，
    // 切换衣物、关闭弹层或重新打开编辑后，旧回调只能失效，不能提交新草稿。
    const editId: string = changed.id;
    const editDraft: GarmentDraft = this.draft;
    this.savingGarment = true;
    this.draft.error = '';
    // 先落盘：publish 与 afterPublish 都由提交链在保存成功之后调用。
    const saved: boolean = await this.commit(candidate, () => {
      // 发布：只有落盘成功后才把新属性并入内存，并收回草稿里的图片所有权。
      this.garments = nextGarments;
      this.selectedItem = changed;
      this.draftImages = []; this.draft.uri = ''; this.originalDraftUri = ''; this.cutoutDraftUri = '';
      this.showSheet = false;
    }, () => {
      this.regenerate(); this.refreshCard(); this.toast('衣物属性已更新');
      if (obsoleteImage.length > 0 && this.repository &&
        !this.garments.some((item: Garment) => item.imageUri === obsoleteImage)) {
        this.repository.discardImage(obsoleteImage).catch(() => {
          hilog.warn(0x1200, 'YiDa', 'Replaced image cleanup failed');
        });
      }
    }, () => {
      if (!this.alive || !this.showSheet || this.sheet !== 'add' ||
        this.selectedItem.id !== editId || this.draft !== editDraft) { return; }
      this.addGarment();
    });
    this.savingGarment = false;
    if (!saved) {
      // 旧图在新快照落盘成功前一直保留，失败时原衣物仍能显示；草稿继续留在表单里。
      this.draft.error = '保存失败：请检查存储空间后重试';
    }
  }

  // 单件编辑表单换图：只替换草稿里的图片，保存成功前不删旧图。
  private clearDraft(): void {
    const uris: string[] = this.draftImages.slice();
    this.draftImages = []; this.draft.uri = ''; this.originalDraftUri = ''; this.cutoutDraftUri = '';
    if (this.repository) {
      for (const uri of uris) {
        if (!this.garments.some((item: Garment) => item.imageUri === uri)) {
          this.repository.discardImage(uri).catch(() => { hilog.warn(0x1200, 'YiDa', 'Draft image cleanup failed'); });
        }
      }
    }
  }

  private async cutoutPhoto(): Promise<void> {
    if (this.cuttingOut || this.importing || !this.repository || this.originalDraftUri.length === 0) { return; }
    // 抠图输出同样使用本应用批量文件前缀，必须服从启动清理门禁。
    if (!this.sweepDone) { this.toast('正在整理本机文件，请稍候再试'); return; }
    if (!cutoutSupported()) {
      this.draft.error = '暂时无法抠图，可继续使用原图'; this.toast(this.draft.error); return;
    }
    if (this.cutoutDraftUri.length > 0) {
      this.invalidateRetry(); this.draft.uri = this.cutoutDraftUri; return;
    }
    const original: string = this.originalDraftUri;
    this.invalidateRetry();
    this.cuttingOut = true; this.draft.error = '';
    try {
      // 输出路径由仓储生成，抠图服务不再自己拼文件名；标识同样每次新取，不复用。
      const uri: string = await cutoutGarment(original, this.repository.cutoutPathFor(this.draftFileKey()));
      if (!this.alive || !this.showSheet || original !== this.originalDraftUri) {
        await this.repository.discardImage(uri); return;
      }
      this.draftImages.push(uri); this.cutoutDraftUri = uri; this.draft.uri = uri;
    } catch (error) {
      if (this.alive && original === this.originalDraftUri) {
        this.draft.error = (error as Error).message || '抠图失败，可重试或使用原图'; this.toast(this.draft.error);
      }
    } finally { this.cuttingOut = false; }
  }

  private async recordWear(feedback: string): Promise<void> {
    if (this.readBlocked) { return; }
    const date: string = localDay();
    const ids: string[] = this.selectedLook.garmentIds;
    if (ids.length === 0) { this.toast('请先选择一套搭'); this.showSheet = false; return; }
    const items: Garment[] = this.itemsFor(this.selectedLook);
    if (items.length !== ids.length || items.some((item: Garment) => item.status !== GarmentStatus.READY)) {
      this.toast('衣物状态已改变，请重新搭配'); this.showSheet = false; return;
    }
    // 同一反馈弹层的失败重试复用记。ID，不把尚未落盘的内存记录当成另一条重复提交。
    const existing: DiaryEntry | undefined = this.diary.find((item: DiaryEntry) =>
      item.id === this.pendingWearId);
    const entry: DiaryEntry = { id: existing ? existing.id : this.pendingWearId, date: date, garmentIds: ids.slice(),
      note: '', photoUri: '', weather: this.weather.available ? this.weather.condition : '手动温度',
      temperature: this.selectedLook.temperature, occasion: this.selectedLook.occasion, feedback: feedback };
    if (this.recordingWear) { return; }
    this.recordingWear = true;
    try {
      await this.addDiaryEntry(entry);
      this.activeIds = ids.slice(); this.showSheet = false; this.persist();
    } catch (error) { this.toast((error as Error).message); }
    finally { this.recordingWear = false; }
  }

  private resetDemo(): void {
    if (this.businessBusy()) { return; }
    this.getUIContext().getPromptAction().showDialog({ title: '重置演示衣橱',
      message: '将清空本机收藏、穿着记录和导入衣物，并恢复 6 件示例衣物。原相册照片不会删除。',
      buttons: [{ text: '取消', color: $r('app.color.text_secondary') },
        { text: '重置', color: $r('app.color.warning') }]
    }).then(async (result) => {
      if (result.index !== 1 || !this.repository) { return; }
      // 对话框打开期间可能有另一项提交完成；确认时再次检查，避免重置覆盖它。
      if (this.businessBusy()) { return; }
      this.invalidateRetry();
      const previous: Garment[] = this.garments.slice();
      const fresh: DemoSnapshot = initialSnapshot();
      // 先落盘；restore(fresh) 放进 publish，保证发布发生在天气补存之前。
      const saved: boolean = await this.commit(fresh, () => {
        this.readBlocked = false; this.lockedIds = []; this.excludedIds = [];
        this.restore(fresh); this.notice = '';
        this.search = ''; this.filterCategory = '全部'; this.filterStatus = '全部状态';
        this.showSaved = false; this.quizStep = 0;
      }, async () => {
        // 重置后的清理只针对"已不再被任何持久化记录引用"的旧图片。
        for (const item of previous) {
          if (item.imageUri.length > 0 && !this.isReferencedImage(item.imageUri)) {
            await this.repository?.discardImage(item.imageUri)
              .catch(() => { this.notice = '部分导入图片尚未清理。'; });
          }
        }
        this.toast('已恢复示例衣橱');
      }, () => { this.resetDemo(); });
      if (!saved) { this.notice = '重置未写入本机，原数据仍然保留。'; }
    }).catch(() => { this.toast('未能完成重置，原数据已保留'); });
  }

  private openCardManager(): void {
    this.persist();
    try {
      formProvider.openFormManager({ bundleName: 'com.chr.Yi_Da', abilityName: 'TodayFormAbility',
        parameters: { 'ohos.extra.param.key.form_dimension': 2, 'ohos.extra.param.key.form_name': 'TodayOutfit',
          'ohos.extra.param.key.module_name': 'entry' } });
    } catch (error) { this.toast('当前系统未能打开卡片管理，请从桌面应用图标添加服务卡片'); }
  }

  // 这是用户主动操作的离线文件迁移，不代表手机和平板已经建立自动同步连接。
  // Picker 打开期间冻结本地修改；卡片唤起与天气更新由既有提交锁延后处理。
  private async exportMigration(): Promise<void> {
    if (this.readBlocked || !this.repository) { throw new Error('本地数据不可读取，暂不能导出'); }
    if (this.navigating()) { throw new Error('正在保存上一项，请稍候再导出'); }
    if (!this.sweepDone) { throw new Error('正在整理本机文件，请稍候再导出'); }
    this.migrationBusy = true;
    try {
      const result: MigrationPickerResult<string> = await exportWardrobeMigrationWithPicker(
        this.context(), this.snapshot(), 'manual-export-' + String(Date.now()), 0);
      if (result.status !== 'saved') { throw new Error(result.message); }
    } finally {
      this.migrationBusy = false;
      this.afterPublish();
    }
  }

  private async importMigration(): Promise<void> {
    if (!this.repository) { throw new Error('本地存储尚未就绪'); }
    if (this.navigating()) { throw new Error('正在保存上一项，请稍候再导入'); }
    if (!this.sweepDone && !this.readBlocked) { throw new Error('正在整理本机文件，请稍候再导入'); }
    this.migrationBusy = true;
    let imported: boolean = false;
    try {
      const picked: MigrationPickerResult<string> = await selectMigrationPackageWithPicker(this.context());
      if (picked.status !== 'selected' || picked.value === undefined) { throw new Error(picked.message); }
      // 从确认文件开始，旧城市的在途天气不得再写进即将导入的快照。
      // 选择器取消时不触碰待处理温度，仍由 finally 走正常补存。
      this.weatherRequest += 1;
      this.commitLock.takeTemperature();
      const target = createCoreFileMigrationTargetAdapter(this.context().filesDir);
      // 手动迁移没有后台 revision 服务。当前本机快照按 revision 0 比较；
      // 同版本且内容不同会要求用户再确认，而不是以时间戳自动覆盖本机衣橱。
      const local: SyncEnvelope<DemoSnapshot> | undefined = this.readBlocked ? undefined :
        createSyncEnvelope(this.snapshot(), 'local-wardrobe', 0);
      const prepared: MigrationPreparationResult<DemoSnapshot> = await prepareWardrobeMigration(
        picked.value, target, local);
      if (prepared.status === 'rejected' || prepared.status === 'stale' ||
        prepared.status === 'duplicate' || prepared.candidate === undefined) {
        throw new Error(prepared.message);
      }
      if (prepared.status === 'conflict') {
        const answer = await this.getUIContext().getPromptAction().showDialog({
          title: '确认覆盖当前衣橱？',
          message: '迁移文件与本机衣橱内容不同。导入后，本机衣物、收藏、日记和试穿记录会以文件内容为准。',
          buttons: [{ text: '保留本机', color: $r('app.color.text_secondary') },
            { text: '覆盖导入', color: $r('app.color.warning') }]
        });
        if (answer.index !== 1) { throw new Error('已取消导入，当前衣橱未改变'); }
      }
      const candidate: WardrobeMigrationCandidate<DemoSnapshot> = prepared.candidate;
      await commitWardrobeMigrationCandidate(candidate, target, {
        validate: (snapshot: DemoSnapshot) => {
          const payload: string = JSON.stringify(snapshot);
          if (new util.TextEncoder().encodeInto(payload).byteLength > 2 * 1024 * 1024) {
            throw new Error('导入后的衣橱快照超过本机容量上限');
          }
          validateSnapshot(snapshot);
        },
        commit: (snapshot: DemoSnapshot) => this.repository ? this.repository.save(snapshot) :
          Promise.reject(new Error('本地存储尚未就绪')),
        publish: (snapshot: DemoSnapshot) => {
          this.invalidateRetry();
          this.readBlocked = false;
          this.lockedIds = [];
          this.excludedIds = [];
          this.restore(snapshot);
          this.weather = { available: false, city: this.city, condition: '', tempMin: 0,
            tempMax: 0, source: '手动温度' };
          this.showSheet = false;
          this.refreshCard();
        }
      }, prepared.status === 'conflict');
      imported = true;
      // 只按仓储允许的批量文件前缀清理。目标适配器同样使用该前缀；
      // referencedImages 会保护刚发布快照仍在使用的图片。
      try {
        await this.repository.sweepOrphans(this.snapshot());
        // 只读恢复启动时尚未做过清理；这次已在迁移锁内完成，不再启动第二轮异步清理。
        this.orphanSwept = true;
        this.sweepDone = true;
      } catch (error) {
        hilog.warn(0x1200, 'YiDa', 'Migration orphan sweep failed');
      }
    } finally {
      this.migrationBusy = false;
      this.afterPublish();
      if (imported) { this.refreshWeather(); }
    }
  }

  private openQuiz(): void {
    // 从已有档案回填，用户可以只改其中一题，不必从头再答一遍。
    this.quizFits = this.profile.fits.slice();
    this.quizPalettes = this.profile.palettes.slice();
    this.quizStyles = this.profile.styles.slice();
    this.quizLayering = this.profile.layering > 0 ? '喜欢' : (this.profile.layering < 0 ? '不喜欢' : '');
    this.quizPattern = this.profile.accessories > 0 ? '喜欢' : (this.profile.accessories < 0 ? '不喜欢' : '');
    this.quizPriority = this.profile.priority;
    this.quizStep = 1;
    this.openSheet('quiz');
  }

  private toggleIn(list: string[], value: string): string[] {
    return list.indexOf(value) >= 0 ? list.filter((entry: string) => entry !== value) : list.concat([value]);
  }

  // Checkbox 、onChange 直接给出目标状态，按状态设置比取反更稳。
  private setIn(list: string[], value: string, checked: boolean): string[] {
    const without: string[] = list.filter((entry: string) => entry !== value);
    return checked ? without.concat([value]) : without;
  }

  private commitProfile(): void {
    if (this.businessBusy()) { return; }
    this.invalidateRetry();
    this.profile = {
      fits: this.quizFits.slice(), palettes: this.quizPalettes.slice(), styles: this.quizStyles.slice(),
      layering: this.quizLayering === '喜欢' ? 1 : (this.quizLayering === '不喜欢' ? -1 : 0),
      accessories: this.quizPattern === '喜欢' ? 1 : (this.quizPattern === '不喜欢' ? -1 : 0),
      priority: this.quizPriority, completed: true
    };
    this.quizStep = QUIZ.length + 1;
    this.regenerate(); this.persist();
  }

  private resetProfile(): void {
    if (this.businessBusy()) { return; }
    this.invalidateRetry();
    this.profile = emptyProfile();
    this.quizFits = []; this.quizPalettes = []; this.quizStyles = [];
    this.quizLayering = ''; this.quizPattern = ''; this.quizPriority = '';
    this.quizStep = 1;
    this.regenerate(); this.persist();
  }

  // 档案摘要只描述已选择的维度，不给出“你是某某风格”的单一结论。
  private profileSummary(): string {
    const parts: string[] = [];
    if (this.profile.fits.length > 0) { parts.push(this.profile.fits.join('、')); }
    if (this.profile.palettes.length > 0) { parts.push(this.profile.palettes.join('、') + '配色'); }
    if (this.profile.styles.length > 0) { parts.push(this.profile.styles.join('、')); }
    if (this.profile.priority.length > 0) { parts.push('看重' + this.profile.priority); }
    return parts.length > 0 ? parts.join(' · ') : '已保存，可随时修';
  }

  // 点击态与禁用态统一处理，符合鸿蒙控件的按压反馈预期。
  @Styles
  pressable() {
    .stateStyles({
      pressed: { .opacity(Theme.pressedOpacity) },
      disabled: { .opacity(Theme.disabledOpacity) }
    })
  }

  @Builder
  private iconButton(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon).fontSize(Theme.iconMd).fontColor([Theme.text])
    }
      .width(Theme.buttonCompact).height(Theme.buttonCompact)
      .backgroundColor(Color.Transparent)
      .accessibilityText(label)
      .pressable()
      .onClick(action)
  }

  @Builder
  private tabLabel(index: number, icon: Resource, name: string) {
    Column({ space: Theme.spaceXs }) {
      SymbolGlyph(icon).fontSize(Theme.iconMd).fontColor([this.tab === index ? Theme.accent : Theme.secondary])
      Text(name).fontSize(Type.caption).fontColor(this.tab === index ? Theme.accent : Theme.secondary)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  private sectionTitle($$: TextPair) {
    Column({ space: Theme.spaceXs }) {
      Text($$.title).fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(2)
      if ($$.subtitle.length > 0) {
        Text($$.subtitle).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
      .margin({ top: Theme.spaceS, bottom: Theme.spaceL })
  }

  @Builder
  private conditions() {
    Column({ space: Theme.spaceM }) {
      Row({ space: Theme.spaceM }) {
        SymbolGlyph($r('sys.symbol.sun_max')).fontSize(Theme.iconMd).fontColor([Theme.success])
        Column({ space: Theme.spaceXs }) {
          Text(this.temperature + '℃').fontSize(Type.section).fontWeight(FontWeight.Medium)
            .fontColor(Theme.text).maxLines(1)
          Text('手动天气 · ' + new Date().toLocaleDateString())
            .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Select(OCCASIONS.map((value: string): SelectOption => { return { value: value }; }))
          .value(this.occasion).font({ size: Type.bodySmall }).fontColor(Theme.text)
          .selectedOptionFontColor(Theme.accent).optionFontColor(Theme.text)
          .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
          .controlSize(ControlSize.SMALL).space(Theme.spaceXs)
          .onSelect((index: number) => {
            if (this.businessBusy()) { return; }
            this.occasion = OCCASIONS[index]; this.changeConditions();
          })
      }.width('100%')
      // 关闭滑块气泡提示：气泡浮在滑轨上方会盖住天气说明，且出现/消失会让版面上下抖动。
      // 温度本身已用大字号实时显示，拖动时同样可见。
      Slider({ value: this.temperature, min: -20, max: 45, step: 1 }).selectedColor(Theme.accent)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (this.businessBusy()) { return; }
          this.temperature = Math.round(value); this.regenerate();
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            // 用户手调温度优先于尚在途的天气结果。
            this.weatherRequest += 1;
            this.invalidateRetry(); this.persist();
          }
        }).accessibilityText('天气温度')
    }.padding(Theme.spaceM).width('100%').backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard).enabled(!this.readBlocked)
  }

  @Builder
  private emptyState($$: TextPair) {
    Column({ space: Theme.spaceM }) {
      SymbolGlyph($r('sys.symbol.shirt')).fontSize(40).fontColor([Theme.secondary])
      Text($$.title).fontSize(Type.cardTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text)
        .maxLines(2).textAlign(TextAlign.Center)
      Text($$.subtitle).fontSize(Type.bodySmall).fontColor(Theme.secondary)
        .textAlign(TextAlign.Center).lineHeight(22).maxLines(4)
    }.width('100%').padding({ top: Theme.spaceXxl, bottom: Theme.spaceXxl, left: Theme.spaceL, right: Theme.spaceL })
  }

  @Builder
  private statusChip(status: GarmentStatus) {
    Text(status).fontSize(Type.caption)
      .fontColor(status === GarmentStatus.READY ? Theme.success : Theme.secondary)
      .padding({ left: Theme.spaceS, right: Theme.spaceS, top: Theme.spaceXs, bottom: Theme.spaceXs })
      .backgroundColor(status === GarmentStatus.READY ? Theme.successSoft : Theme.surfaceSoft)
      .borderRadius(Theme.radiusInput)
  }

  @Builder
  private outfitCard(look: Outfit, editable: boolean) {
    Column({ space: Theme.spaceM }) {
      if (!editable) {
        Text(look.name).fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).width('100%').maxLines(2)
          .onClick(() => this.openOutfitDetail(look))
      }
      Row({ space: Theme.spaceXs }) {
        Text(look.occasion + ' · ' + look.temperature + '℃').fontSize(Type.cardTitle)
          .fontWeight(FontWeight.Medium).fontColor(Theme.text).layoutWeight(1).maxLines(1)
        this.iconButton($r('sys.symbol.share'), '分享搭配清单', () => this.shareLook(look))
        this.iconButton(this.saved.some((item: Outfit) => item.id === look.id) ? $r('sys.symbol.heart_fill') :
          $r('sys.symbol.heart'), '收藏搭配', () => this.saveLook(look))
      }.width('100%')
      Row({ space: Theme.spaceS }) {
        ForEach(this.itemsFor(look), (item: Garment) => {
          Column({ space: Theme.spaceS }) {
            Image(garmentImage(item)).width('100%').height(126).objectFit(ImageFit.Contain)
              .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
              .accessibilityText(item.name)
              .onClick(() => { this.selectedItem = item; this.openSheet('detail'); })
            Text(item.category).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
            if (editable) {
              Row() {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(Theme.iconSm).fontColor([Theme.secondary])
                }.width('50%').height(Theme.buttonCompact).backgroundColor(Color.Transparent)
                  .accessibilityText('替换' + item.category).pressable()
                  .onClick(() => this.replace(look, item.id))
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph(this.lockedIds.indexOf(item.id) >= 0 ? $r('sys.symbol.lock_fill') : $r('sys.symbol.lock_open'))
                    .fontSize(Theme.iconSm)
                    .fontColor([this.lockedIds.indexOf(item.id) >= 0 ? Theme.accent : Theme.secondary])
                }.width('50%').height(Theme.buttonCompact).backgroundColor(Color.Transparent)
                  .accessibilityText('锁定或解' + item.name).pressable()
                  .onClick(() => this.toggleLock(item))
              }.width('100%')
            }
          }.layoutWeight(1)
        }, (item: Garment) => item.id)
      }.width('100%')
      Text(look.reason).fontSize(Type.bodySmall).fontColor(Theme.secondary).lineHeight(22).width('100%')
      Row({ space: Theme.spaceS }) {
        Button('试穿样片', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonHeight)
          .layoutWeight(1).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
          .borderRadius(Theme.radiusPill).pressable()
          .onClick(() => { this.openTryOn(); })
        Button(editable ? '今天穿这套' : '编辑画布', { type: ButtonType.Normal }).fontSize(Type.buttonSmall)
          .height(Theme.buttonHeight).layoutWeight(1).backgroundColor(Theme.accent).fontColor(Color.White)
          .borderRadius(Theme.radiusPill).pressable()
          .onClick(() => {
            if (editable) {
              this.activeIds = look.garmentIds.slice(); this.persist(); this.beginWear(look);
            } else { this.openStudio(look); }
          })
      }.width('100%')
    }.padding(Theme.spaceL).width('100%').backgroundColor(Theme.surface).borderRadius(Theme.radiusCard)
      .shadow({ radius: 12, color: Theme.shadow, offsetX: 0, offsetY: 2 })
      .enabled(!this.readBlocked).margin({ bottom: Theme.spaceM })
  }

  @Builder
  private todayPage() {
    // 首页独立成组件，包含真实天气、快捷入口、今日推荐与最近日记。
    HomePage({
      garmentCount: this.garments.length,
      todayRecorded: this.todayRecorded(),
      city: this.weather.available && this.weather.city.length > 0 ? this.weather.city : this.cityName(),
      weather: this.weather.available ? this.weather.condition : '手动天气',
      tempMin: this.weather.available ? this.weather.tempMin : this.temperature,
      tempMax: this.weather.available ? this.weather.tempMax : this.temperature,
      weatherAvailable: this.weather.available,
      outfits: this.plans,
      diary: this.diary,
      garments: this.garments,
      onAddGarment: () => { this.openAdd(); },
      onOpenWardrobe: () => { this.switchTab(1); },
      onRecordOutfit: () => { this.recordToday(); },
      onOpenDiy: () => { this.openStudio(); },
      onOpenDiary: () => { this.openRoute('diary'); },
      onOpenTryOn: () => { this.openTryOn(); },
      onOpenAssistant: () => { this.openAssistant(); },
      onSaveOutfit: (look: Outfit) => { this.saveLook(look); },
      onRecordLook: (look: Outfit) => { this.beginWear(look); },
      onOpenProfile: () => { this.switchTab(3); },
      onOpenCity: () => { this.openSheet('city'); },
      monthRecorded: this.monthRecordedDays(),
      onOpenBanner: () => {
        if (this.garments.length < 5) { this.openAdd(); } else { this.openRoute('diary'); }
      },
      onOpenOutfit: (look: Outfit) => { this.openOutfitDetail(look); },
      onOpenTile: (name: string) => { this.openTile(name); }
    })
  }

  // 独立页面：批量录入、搭配DIY、搭配详情、穿搭日记、AI 试穿。
  //
  // 批量录入页自己带顶部返回条、内部滚动区与固定提交区，所以它拿到的是一个有界布局。
  // 不再套外。Scroll——把带内。Scroll 的整页塞进外。Scroll，底部提交区就没法固定可达。
  // 其余独立页沿用原有的"整页滚动"结构。
  @Builder
  private routePage() {
    Column() {
      if (this.mainRoute === 'garmentImport') {
        GarmentImportPage({
          items: this.importItems,
          currentIndex: this.importIndex,
          garmentCount: this.garments.length,
          readBlocked: this.readBlocked,
          busy: this.commitInFlight,
          recognitionMessage: this.importRecognitionHint()?.message || '',
          recognitionColor: this.importRecognitionHint()?.color || '',
          recognitionCategory: this.importRecognitionHint()?.subcategory || '',
          recognitionBusy: this.recognizingImportTaskId.length > 0,
          onOpenAssistant: () => { this.openAssistant(); },
          onRecognize: (index: number) => { this.recognizeImportColor(index); },
          onUseRecognition: (index: number) => { this.useRecognizedColor(index); },
          onUseCategory: (index: number) => { this.useRecognizedCategory(index); },
          onPick: () => { this.pickImportPhotos(); },
          onSample: (id: string) => { this.pickImportSample(id); },
          onSelect: (index: number) => { this.importMove(index); },
          onMove: (index: number) => { this.importMove(index); },
          onConfirm: (index: number) => { this.importConfirm(index); },
          onSkip: (index: number) => { this.importSkip(index); },
          onRetry: (index: number) => { this.importRetry(index); },
          onCutout: (index: number) => { this.importCutout(index); },
          onOriginal: (index: number) => { this.importUseOriginal(index); },
          onName: (index: number, value: string) => { this.importName(index, value); },
          onCategory: (index: number, value: number) => { this.importCategory(index, value); },
          onSubcategory: (index: number, value: string) => { this.importSubcategory(index, value); },
          onMaterial: (index: number, value: string) => { this.importMaterial(index, value); },
          onColor: (index: number, value: string) => { this.importColor(index, value); },
          onMinTemp: (index: number, value: number) => { this.importMinTemp(index, value); },
          onMaxTemp: (index: number, value: number) => { this.importMaxTemp(index, value); },
          onOccasions: (index: number, value: string[]) => { this.importOccasions(index, value); },
          onExit: () => { this.importExit(); }
        })
      } else {
        Row({ space: Theme.spaceS }) {
          this.iconButton($r('sys.symbol.arrow_left'), '返回', () => this.closeRoute())
          Text(this.routeTitle()).fontSize(Type.section).fontWeight(FontWeight.Medium)
            .fontColor(Theme.text).layoutWeight(1).maxLines(1)
          DadaEntry({ state: this.dadaVisualState(),
            pulseKey: this.dadaContext().key, onOpen: () => this.openAssistant() })
        }.width('100%').height(Theme.navBarHeight)
          .padding({ left: Theme.spaceS, right: Theme.pagePadding })
        if (this.mainRoute === 'tryOn') {
          // 能力边界置于滚动区外，素材选择、过程、结果和记录滚动时都持续可见。
          Text(TRY_ON_BOUNDARY).fontSize(Type.caption).fontColor(Theme.accent).width('100%')
            .padding({ left: Theme.pagePadding, right: Theme.pagePadding, top: 8, bottom: 8 })
            .backgroundColor(Theme.accentSoft)
        }
        Scroll(this.routeScroller) {
          Column() {
            if (this.mainRoute === 'outfitStudio') {
              OutfitStudioPage({
                initialOutfit: this.studioDraft,
                garments: this.garments,
                temperature: this.temperature,
                occasion: this.occasion,
                lockedIds: this.lockedIds,
                excludedIds: this.excludedIds,
                onSave: (look: Outfit) => this.upsertOutfit(look),
                onDraftChange: (look: Outfit) => {
                  // 画布继续编辑后，上一份失败候选不再代表当前草稿。
                  this.invalidateRetry(); this.studioDraft = look;
                },
                onOpenDetail: (look: Outfit) => { this.openOutfitDetail(look); }
              })
            } else if (this.mainRoute === 'outfitDetail') {
              OutfitDetailPage({
                outfit: this.selectedLook,
                garments: this.garments,
                lockedIds: this.lockedIds,
                excludedIds: this.excludedIds,
                savedIds: this.saved.map((item: Outfit) => item.id),
                onToggleSave: (look: Outfit) => { this.selectedLook = look; this.saveLook(look); },
                onWear: (look: Outfit) => { this.beginWear(look); },
                onTryOn: (look: Outfit) => { this.selectedLook = look; this.openTryOn(); },
                onEditCanvas: (look: Outfit) => { this.openStudio(look); },
                onClose: () => { this.closeRoute(); }
              })
            } else if (this.mainRoute === 'diary') {
              DiaryPage({
                diary: this.diary,
                garments: this.garments,
                saved: this.saved,
                onAddEntry: (entry: DiaryEntry) => this.addDiaryEntry(entry),
                onDeleteEntry: (id: string) => this.deleteDiaryEntry(id),
                onOpenOutfit: (look: Outfit) => { this.openOutfitDetail(look); }
              })
            } else {
              TryOnPage({
                tasks: this.tryOnTasks,
                initialSceneId: this.tryOnSceneId,
                command: this.tryOnCommand,
                onCommandConsumed: (id: number) => {
                  if (this.tryOnCommand.id === id) { this.tryOnCommand = { id: 0, action: 'start', sceneId: this.tryOnSceneId }; }
                },
                onSceneChange: (id: string) => { this.tryOnSceneId = id; },
                onStageChange: (stage: TryOnStage) => { this.tryOnStage = stage; },
                onSubmit: (sceneId: string) => this.submitTryOn(sceneId),
                onDeleteTask: (id: string) => this.deleteTryOnTask(id),
                onReveal: () => { this.routeScroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
              })
            }
          }.width('100%').constraintSize({ maxWidth: CONTENT_MAX_WIDTH }).padding({ bottom: Theme.spaceXl })
            .enabled(!this.readBlocked)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }
    }
      .width('100%').layoutWeight(1).backgroundColor(Theme.background)
  }

  private routeTitle(): string {
    if (this.mainRoute === 'garmentImport') { return '批量录入衣物'; }
    if (this.mainRoute === 'outfitStudio') { return '搭配工作'; }
    if (this.mainRoute === 'outfitDetail') { return this.selectedLook.name.length > 0 ? this.selectedLook.name : '搭配详情'; }
    if (this.mainRoute === 'diary') { return '穿搭日记'; }
    return 'AI 试穿';
  }

  @Builder
  private wardrobePage() {
    WardrobePage({
      garments: this.garments,
      search: this.search,
      filterCategory: this.filterCategory,
      filterStatus: this.filterStatus,
      readBlocked: this.readBlocked,
      onSearch: (value: string) => { this.search = value; },
      onAddGarment: () => { if (!this.readBlocked) { this.openAdd(); } },
      onOpenItem: (item: Garment) => { this.selectedItem = item; this.openSheet('detail'); },
      onSetStatus: (id: string, status: GarmentStatus) => { this.setStatusById(id, status); },
      onBatchEdit: (ids: string[], status: GarmentStatus | undefined, season: string, tag: string) => {
        this.batchEditGarments(ids, status, season, tag);
      }
    })
  }

  @Builder
  private outfitPage() {
    Column({ space: Theme.spaceM }) {
      this.sectionTitle({ title: '搭配工作', subtitle: '' })
      // 分段控件：选中态用品牌色描边与浅底，未选中态保持中性。
      Row() {
        Button('搭配', { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonCompact)
          .borderRadius(Theme.radiusPill).fontSize(Type.buttonSmall)
          .backgroundColor(!this.showSaved ? Theme.accentSoft : Theme.surfaceSoft)
          .fontColor(!this.showSaved ? Theme.accent : Theme.secondary)
          .pressable().onClick(() => this.showSaved = false)
        Button('收藏 ' + this.saved.length, { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonCompact)
          .borderRadius(Theme.radiusPill).fontSize(Type.buttonSmall)
          .backgroundColor(this.showSaved ? Theme.accentSoft : Theme.surfaceSoft)
          .fontColor(this.showSaved ? Theme.accent : Theme.secondary)
          .pressable().onClick(() => this.showSaved = true)
      }.width('100%').padding(Theme.spaceXs).backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusPill)
      if (!this.showSaved) {
        this.conditions()
        if (this.lockedIds.length > 0 || this.excludedIds.length > 0) {
          Row({ space: Theme.spaceS }) {
            SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(Theme.iconSm).fontColor([Theme.accent])
            Text('锁定 ' + this.lockedIds.length + ' 件 · 排除 ' + this.excludedIds.length + ' 件')
              .fontSize(Type.caption).fontColor(Theme.accent).layoutWeight(1).maxLines(2)
            Button('清除', { type: ButtonType.Normal }).height(Theme.buttonCompact).fontSize(Type.buttonSmall)
              .backgroundColor(Theme.accentSoft).fontColor(Theme.accent).borderRadius(Theme.radiusPill)
              .pressable().onClick(() => { this.lockedIds = []; this.excludedIds = []; this.changeConditions(); })
          }.width('100%').padding(Theme.spaceM).backgroundColor(Theme.accentSoft)
            .borderRadius(Theme.radiusCard)
        }
        if (this.plans.length === 0) { this.emptyState({ title: '需要调整搭配条', subtitle: this.explanation }) }
        ForEach(this.plans, (look: Outfit) => { this.outfitCard(look, true) }, (look: Outfit) => look.id)
      } else {
        if (this.saved.length === 0) { this.emptyState({ title: '还没有收藏的搭配', subtitle: '喜欢的组合，都可以留在这里。' }) }
        ForEach(this.saved, (look: Outfit) => { this.outfitCard(look, false) }, (look: Outfit) => look.id)
      }
    }.width('100%').constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
      .padding({ left: Theme.pagePadding, right: Theme.pagePadding, bottom: Theme.spaceXl })
  }

  @Builder
  // $$ 按引用传递，让收藏、穿着反馈及重置后的数字立即更新；普通数值参数只保留首次构建的值。
  private stat($$: StatValue) {
    Column({ space: Theme.spaceXs }) {
      Text(String($$.value)).fontSize(Type.display).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(1)
      Text($$.label).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
    }.layoutWeight(1)
  }

  @Builder
  private profilePage() {
    // 「我的」独立成组件：会员体验、完善度、档案入口、试穿记录都在里面。
    ProfilePage({
      membership: this.membership,
      body: this.body,
      tasks: this.tryOnTasks,
      wardrobePercent: completeness(this.snapshot()).percent,
      garmentCount: this.garments.length,
      profileSummary: this.profileSummary(),
      profileDone: this.profile.completed,
      cardSpaces: this.cardSpaces,
      onOpenQuiz: () => { this.openQuiz(); },
      onOpenBody: () => { this.openSheet('body'); },
      onClaimTrial: () => { this.claimTrial(); },
      onOpenTryOn: (sceneId?: string) => { this.openTryOn(sceneId); },
      onOpenCardManager: () => { this.openCardManager(); },
      onOpenTransfer: () => { this.openSheet('transfer'); },
      onReset: () => { this.resetDemo(); }
    })
  }

  @Builder
  private sheetTitle(title: string) {
    Text(title).fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text)
      .width('100%').padding({ right: 44 }).maxLines(2)
  }

  // 多选题用系。Checkbox：多选语义清晰，勾选状态不依赖颜色。
  @Builder
  private quizCheck(label: string, checked: boolean, action: (value: boolean) => void) {
    Row({ space: Theme.spaceS }) {
      Checkbox({ name: label })
        .select(checked)
        .selectedColor(Theme.accent)
        .shape(CheckBoxShape.ROUNDED_SQUARE)
        .width(Theme.iconMd).height(Theme.iconMd)
        .onChange(action)
      Text(label).fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(1)
    }
      .width('100%').height(Theme.buttonHeight)
      .padding({ left: Theme.spaceM, right: Theme.spaceM })
      .backgroundColor(checked ? Theme.accentSoft : Theme.surfaceSoft)
      .borderRadius(Theme.radiusCard)
      .onClick(() => action(!checked))
  }

  @Builder
  private quizSingle(label: string, selected: boolean, action: () => void) {
    Button(label, { type: ButtonType.Normal }).fontSize(Type.buttonSmall)
      .height(Theme.buttonHeight).width('100%').borderRadius(Theme.radiusCard)
      .backgroundColor(selected ? Theme.accentSoft : Theme.surfaceSoft)
      .fontColor(selected ? Theme.accent : Theme.text)
      .border({ width: 1, color: selected ? Theme.accent : Theme.line })
      .pressable()
      .onClick(action)
  }

  @Builder
  private quizResult() {
    Column({ space: Theme.spaceM }) {
      this.sheetTitle('你的穿搭偏好')
      Text('这些是可以随时修改的倾向，不是固定标签。推荐只会据此调整顺序，不会排除你的衣物')
        .fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(22).width('100%')
      this.resultRow('版型倾向', this.profile.fits.length > 0 ? this.profile.fits.join('、') : '尚未选择')
      this.resultRow('配色偏好', this.profile.palettes.length > 0 ? this.profile.palettes.join('、') : '尚未选择')
      this.resultRow('风格倾向', this.profile.styles.length > 0 ? this.profile.styles.join('、') : '尚未选择')
      this.resultRow('叠穿接受', this.profile.layering > 0 ? '较高' : (this.profile.layering < 0 ? '较低' : '中等'))
      this.resultRow('图案与配饰', this.profile.accessories > 0 ? '较高' : (this.profile.accessories < 0 ? '较低' : '中等'))
      this.resultRow('出门优先级', this.profile.priority.length > 0 ? this.profile.priority : '尚未选择')
      Button('修改偏好', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
        .fontSize(Type.button).pressable().onClick(() => this.openQuiz())
      Button('重新测验', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
        .fontSize(Type.button).pressable().onClick(() => this.resetProfile())
      Button('开始整理衣橱', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Color.White)
        .fontSize(Type.button).pressable().onClick(() => { this.showSheet = false; this.switchTab(1); })
    }.width('100%')
  }

  @Builder
  private resultRow(label: string, value: string) {
    Row({ space: Theme.spaceM }) {
      Text(label).fontSize(Type.bodySmall).fontColor(Theme.secondary).maxLines(1)
      Blank()
      Text(value).fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(2).textAlign(TextAlign.End)
    }.width('100%').padding(Theme.spaceM).backgroundColor(Theme.surfaceSoft)
      .borderRadius(Theme.radiusCard)
  }

  // 题目文字放在独立橱'@Builder 里：直接写在分支里时 ArkUI 会复用同分支的组件实例'，
  // 切到下一题时题干仍显示上一题的内容。
  @Builder
  private quizQuestionTitle() {
    Text(QUIZ[this.quizStep - 1].title).fontSize(Type.title).fontWeight(FontWeight.Bold)
      .fontColor(Theme.text).width('100%').padding({ right: 44 }).maxLines(2)
  }

  @Builder
  private quizQuestionHint() {
    Text(`。${this.quizStep} / ${QUIZ.length} 第· ${QUIZ[this.quizStep - 1].hint}`)
      .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
  }

  @Builder
  private quizSheet() {
    Column({ space: Theme.spaceL }) {
      if (this.quizStep > QUIZ.length) {
        this.quizResult()
      } else {
        this.quizQuestionTitle()
        this.quizQuestionHint()
        if (this.quizStep === 1) {
          Column({ space: Theme.spaceS }) {
            ForEach(FITS, (value: string) => {
              this.quizCheck(value, this.quizFits.indexOf(value) >= 0,
                (checked: boolean) => { this.quizFits = this.setIn(this.quizFits, value, checked); })
            }, (value: string) => value)
          }.width('100%')
        } else if (this.quizStep === 2) {
          Column({ space: Theme.spaceS }) {
            ForEach(PALETTES, (value: string) => {
              this.quizCheck(value, this.quizPalettes.indexOf(value) >= 0,
                (checked: boolean) => { this.quizPalettes = this.setIn(this.quizPalettes, value, checked); })
            }, (value: string) => value)
          }.width('100%')
        } else if (this.quizStep === 3) {
          Column({ space: Theme.spaceS }) {
            ForEach(STYLES, (value: string) => {
              this.quizCheck(value, this.quizStyles.indexOf(value) >= 0,
                (checked: boolean) => { this.quizStyles = this.setIn(this.quizStyles, value, checked); })
            }, (value: string) => value)
          }.width('100%')
        } else if (this.quizStep === 4) {
          Column({ space: Theme.spaceS }) {
            ForEach(['喜欢', '无所谓', '不喜欢'], (value: string) => {
              this.quizSingle(value, this.quizLayering === value, () => { this.quizLayering = value; })
            }, (value: string) => value)
          }.width('100%')
        } else if (this.quizStep === 5) {
          Column({ space: Theme.spaceS }) {
            ForEach(['喜欢', '无所谓', '不喜欢'], (value: string) => {
              this.quizSingle(value, this.quizPattern === value, () => { this.quizPattern = value; })
            }, (value: string) => value)
          }.width('100%')
        } else {
          Column({ space: Theme.spaceS }) {
            ForEach(['舒适', '正式感', '个性表达', '显瘦'], (value: string) => {
              this.quizSingle(value, this.quizPriority === value, () => { this.quizPriority = value; })
            }, (value: string) => value)
          }.width('100%')
        }
        Row({ space: Theme.spaceM }) {
          Button('上一题', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonHeight)
            .layoutWeight(1).borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft)
            .fontColor(Theme.text).enabled(this.quizStep > 1).pressable()
            .onClick(() => { if (this.quizStep > 1) { this.quizStep = this.quizStep - 1; } })
          Button('不确定', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonHeight)
            .layoutWeight(1).borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft)
            .fontColor(Theme.secondary).pressable()
            .onClick(() => {
              if (this.quizStep < QUIZ.length) { this.quizStep = this.quizStep + 1; } else { this.commitProfile(); }
            })
          Button(this.quizStep < QUIZ.length ? '下一题' : '完成', { type: ButtonType.Normal })
            .fontSize(Type.buttonSmall).height(Theme.buttonHeight).layoutWeight(1)
            .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Color.White).pressable()
            .onClick(() => {
              if (this.quizStep < QUIZ.length) { this.quizStep = this.quizStep + 1; } else { this.commitProfile(); }
            })
        }.width('100%')
      }
    }.width('100%')
  }

  @Builder
  private detailSheet() {
    Column({ space: Theme.spaceL }) {
      this.sheetTitle(this.selectedItem.name)
      Image(garmentImage(this.selectedItem)).width('100%').height(240).objectFit(ImageFit.Contain)
        .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusCard)
      Text(this.selectedItem.category + ' · ' + this.selectedItem.color + ' · ' + this.selectedItem.minTemp +
        ' – ' + this.selectedItem.maxTemp + '℃').fontSize(Type.bodySmall).fontColor(Theme.secondary).width('100%')
      if ((this.selectedItem.subcategory || '').length > 0 || (this.selectedItem.material || '').length > 0) {
        Text([this.selectedItem.subcategory || '', this.selectedItem.material || '']
          .filter((value: string) => value.length > 0).join(' · '))
          .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
      }
      Text('已穿 ' + this.selectedItem.wearCount + ' 次 · ' + this.selectedItem.occasions.join('、'))
        .fontSize(Type.caption).fontColor(Theme.secondary).width('100%')
      Text('推荐偏好').fontSize(Type.body).fontColor(Theme.text).width('100%')
      Text(this.selectedItem.recommendationBias === 1 ? '已标记为优先推荐' :
        this.selectedItem.recommendationBias === -1 ? '已标记为少推荐' : '当前为中性，不改变推荐顺序')
        .fontSize(Type.caption).fontColor(Theme.secondary).width('100%')
      Row({ space: Theme.spaceS }) {
        Button('多推荐', { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill)
          .backgroundColor(this.selectedItem.recommendationBias === 1 ? Theme.accent : Theme.accentSoft)
          .fontColor(this.selectedItem.recommendationBias === 1 ? Color.White : Theme.accent)
          .enabled(!this.readBlocked).onClick(() => { this.setRecommendationBias(1); })
        Button('少推荐', { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill)
          .backgroundColor(this.selectedItem.recommendationBias === -1 ? Theme.accent : Theme.accentSoft)
          .fontColor(this.selectedItem.recommendationBias === -1 ? Color.White : Theme.accent)
          .enabled(!this.readBlocked).onClick(() => { this.setRecommendationBias(-1); })
        Button('中性', { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft).fontColor(Theme.secondary)
          .enabled(!this.readBlocked).onClick(() => { this.setRecommendationBias(0); })
      }.width('100%')
      Button('编辑衣物', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
        .fontSize(Type.button).enabled(!this.readBlocked).onClick(() => this.openEdit())
      Row({ space: Theme.spaceM }) {
        Text('衣物状态').fontSize(Type.body).fontColor(Theme.text).layoutWeight(1).maxLines(1)
        Select(STATUSES.map((value: GarmentStatus): SelectOption => { return { value: value }; })).value(this.selectedItem.status)
          .font({ size: Type.bodySmall }).fontColor(Theme.text)
          .selectedOptionFontColor(Theme.accent).optionFontColor(Theme.text)
          .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
          .onSelect((index: number) => this.changeStatus(STATUSES[index]))
          .enabled(!this.readBlocked)
      }.width('100%')
      Button('围绕这件', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Color.White).fontSize(Type.button)
        .enabled(!this.readBlocked).pressable().onClick(() => {
          if (this.lockedIds.indexOf(this.selectedItem.id) < 0) { this.toggleLock(this.selectedItem); }
          this.showSheet = false; this.switchTab(2); this.showSaved = false;
        })
      Button('本轮排除这件', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
        .fontSize(Type.button).enabled(!this.readBlocked).pressable().onClick(() => {
          this.lockedIds = this.lockedIds.filter((id: string) => id !== this.selectedItem.id);
          if (this.excludedIds.indexOf(this.selectedItem.id) < 0) { this.excludedIds = this.excludedIds.concat([this.selectedItem.id]); }
          this.changeConditions(); this.showSheet = false; this.switchTab(2);
        })
    }.width('100%')
  }

  @Builder
  private addSheetBody() {
    AddGarmentSheet({
      draft: this.draft,
      importing: this.importing,
      cuttingOut: this.cuttingOut,
      hasOriginal: this.originalDraftUri.length > 0,
      showingOriginal: this.draft.uri === this.originalDraftUri,
      onCutout: () => this.cutoutPhoto(),
      onRestoreOriginal: () => { this.draft.uri = this.originalDraftUri; this.draft.error = ''; },
      readBlocked: this.readBlocked,
      editing: this.editingGarment,
      saving: this.savingGarment,
      existingImage: garmentImage(this.selectedItem),
      onPickPhoto: () => this.pickPhoto(),
      onConfirm: () => this.addGarment()
    })
  }

  @Builder
  private feedbackSheet() {
    Column({ space: Theme.spaceL }) {
      this.sheetTitle('今天穿得怎么样？')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(['合服', '偏冷', '偏热', '不舒', '喜欢'], (feedback: string) => {
          Button(feedback, { type: ButtonType.Normal }).width('44%').height(Theme.buttonHeight)
            .margin(Theme.spaceXs).borderRadius(Theme.radiusPill).fontSize(Type.button)
            .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
            .pressable().onClick(() => this.recordWear(feedback))
        })
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private sheetContent() {
    Scroll() {
      Column() {
        if (this.sheet === 'detail') { this.detailSheet() }
        else if (this.sheet === 'add') { this.addSheetBody() }
        else if (this.sheet === 'quiz') { this.quizSheet() }
        else if (this.sheet === 'body') { BodyProfileSheet({ body: this.body,
          onSave: (draft: BodyProfile) => this.saveBodyProfile(draft) }) }
        else if (this.sheet === 'transfer') { SyncTransferSheet({
          onExport: () => this.exportMigration(),
          onImport: () => this.importMigration() }) }
        else if (this.sheet === 'assistant') { AssistantSheet({
          messages: this.agentMessages,
          outfits: this.agentOutfits,
          garments: this.garments,
          context: this.assistantContext,
          state: this.recognizingImportTaskId.length > 0 ? DadaState.WORKING : this.dadaState,
          feedback: this.dadaFeedback,
          busy: this.assistantBusy || this.recognizingImportTaskId.length > 0 || presentationRunning(this.tryOnStage),
          recognitionMessage: this.importRecognitionHint()?.message || '',
          recognitionColor: this.importRecognitionHint()?.color || '',
          recognitionCategory: this.importRecognitionHint()?.subcategory || '',
          onSubmit: (input: string) => { this.submitAssistant(input); },
          onQuick: (input: string) => { this.submitAssistant(input); },
          onApply: (look: Outfit) => { this.applyAgentOutfit(look).catch(() => {}); },
          onAction: (action: DadaAction, input: string) => { this.dadaAction(action, input); }
        }) }
        else if (this.sheet === 'city') {
          CityPickerSheet({ currentCity: this.city, currentTemperature: this.temperature,
            weatherAvailable: this.weather.available, weatherSource: this.weather.source,
            onPick: (city: CityOption, temperature: number) => this.applyCity(city, temperature),
            onUseLocation: () => { this.refreshWeatherAtLocation(); } })
        }
        else { this.feedbackSheet() }
      }.width('100%').constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
        .padding({ left: Theme.spaceXl, right: Theme.spaceXl, top: Theme.spaceXl, bottom: Theme.spaceXxl })
    }.width('100%').height('100%').align(Alignment.TopStart).backgroundColor(Theme.background)
      // 内容比半模态本体晚 50ms 起势、向上归位，避免"整块面板 + 内容"同时硬出现。
      .opacity(this.sheetEntered ? 1 : 0)
      .translate({ y: this.sheetEntered ? 0 : 24 })
      .animation({ duration: 280, curve: Curve.FastOutSlowIn })
  }

  // 顶部两个悬浮胶囊：左（品牌）、右（添加），
  //
  // 左胶囊不再放城市与温度：首页那张天气卡已经显示同一份信息，两处重复。
  // 顶栏是全局常驻层，只承担品牌识别；城市与温度的查看与切换归天气卡（它带 chevron 入口）。
  //
  // 两个胶囊都自己铺材质且底色透明——材质滤镜是半透明的，一旦给实底就成死白板，光感全无。
  // 材质。capsuleMaterial：胶囊面积小。2% 白的材质层在浅色页面上看不出形状。
  @Builder
  private topCapsules() {
    Row() {
      Row() {
        Text('艺起').fontSize(Type.cardTitle).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).maxLines(1)
      }
        .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: Theme.line })
        .borderRadius(Theme.radiusPill)
        .clip(true)
        .shadow(Theme.floatShadow)
        .systemMaterial(capsuleMaterial())

      Blank()

      DadaEntry({ state: this.dadaVisualState(), pulseKey: this.dadaContext().key,
        onOpen: () => this.openAssistant() })
      Row() {
        SymbolGlyph($r('sys.symbol.plus')).fontSize(Theme.iconMd).fontColor([Theme.accent])
      }
        .width(48).height(48).margin({ left: 8 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: Theme.line })
        .borderRadius(Theme.radiusPill)
        .clip(true)
        .shadow(Theme.floatShadow)
        .systemMaterial(capsuleMaterial())
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .onClick(() => { if (!this.readBlocked) { this.openAdd(); } })
    }
      // 自定义栈区没有系统菜单那圈内边距，右胶囊会被挤出屏幕。
      // 实测屏宽 628vp、胶囊右缘需要落在此之内，所以左右各。24vp。
      .padding({ left: Theme.spaceL, right: Theme.spaceL })
      .width('100%')
      .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack() {
      if (this.mainRoute === 'tabs' && this.tab === 0) { HomeBackdrop() }
    Column() {
      if (this.mainRoute === 'tabs') {
        // 顶栏用官。HdsNavigation，但标题区做成两个悬浮胶囊（官方"顶部悬浮区域"的形态）—
        // 左胶囊放品牌与当前城市（可点换城市），右胶囊是独立的圆形添加入口。
        // 胶囊底色全透明，让标题栏的系统材质透出来——这才是沉浸光感的观感。
        // 组件没有现成。官方胶囊"，官方图里的胶囊也是自绘的；这里。HdsNavigation 。
        // stackBuilder 承载左胶囊，再借标题栏自身的材质让光感透出来。
        HdsNavigation() {
          this.mainTabs()
        }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .titleMode(HdsNavigationTitleMode.MINI)
          .hideBackButton(true)
          // 状态栏文字颜色。官方默认值是 '#E5FFFFFF'（半透明白），在浅色页面上等于看不见—。
          // 这正是「滑到顶部时状态栏时间消失」的原因：未滚动时用默认白字。
          // 滚动底HdsNavigation 的滚动效果才把文字转成深色。
          // 本页底色始终是浅色，所以两段样式都用深色文字；深色模式取反。
          .systemBarStyle(
            { statusBarContentColor: this.statusBarInk() },
            { statusBarContentColor: this.statusBarInk() }
          )
          .titleBar({
            // 关键：maskExtraHeight 让遮罩比标题栏多延展一段，内容滚上来时是渐隐，
            // 而不是被标题栏下沿一刀切断（用户报在蒙版遮挡"就是这个）。
            style: {
              scrollEffectOpts: {
                enableScrollEffect: true,
                // IMMERSIVE_GRADIENT_BLUR 是官方给沉浸光感配的渐变模糊浮
                scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
              },
              // 未滚动时：透明把+ 材质，胶囊自己透光。
              originalStyle: {
                backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 40 },
                contentStyle: {}
              },
              // 滚动后：内容滚到标题栏下方，收实底色保证正文可读。
              scrollEffectStyle: {
                backgroundStyle: { backgroundColor: Theme.background, maskExtraHeight: 40 },
                contentStyle: {}
              }
            },
            content: {
              title: { mainTitle: '' },
              // 左右两个胶囊都在 stackBuilder 里自绘。
              // 不要再配 menu：menu 项会与这里的自绘胶囊同时渲染。
              // 结果是两个加号叠在一起（一个系统灰底、一个自绘透光）从
              stackBuilder: (): void => { this.topCapsules() }
            }
          })

        if (this.notice.length > 0) {
          Text(this.notice).fontSize(Type.caption).fontColor(Theme.warning).width('100%')
            .padding(Theme.spaceM).backgroundColor(Theme.warningSoft).borderRadius(Theme.radiusCard)
            .onClick(() => { if (!this.readBlocked) { this.retryPersist(); } })
        }
      }
    }
      .width('100%').height('100%')
      // 四入口层：靠透明度与位移做过渡，不用 if/else 换子树为
      // 换子树时挂在容器上的 transition 不会播（实测为2 秒时长下也瞬间完成）在
      // 常驻 + 属性动画才稳定生效。
      .opacity(this.mainRoute === 'tabs' ? 1 : 0)
      .translate({ x: this.mainRoute === 'tabs' ? 0 : -32 })
      // 不可见图层不能吃掉点击，否则独立页上的按钮会被下面的四入口层挡住浮
      .hitTestBehavior(this.mainRoute === 'tabs' ? HitTestMode.Default : HitTestMode.None)
      .visibility(this.mainRoute === 'tabs' ? Visibility.Visible : Visibility.Hidden)

    // 独立页层：始终挂载在四入口之上，进入时从右侧归位。
    Column() {
      if (this.mainRoute !== 'tabs') { this.routePage() }
    }
      .width('100%').height('100%')
      .opacity(this.mainRoute === 'tabs' ? 0 : 1)
      .translate({ x: this.mainRoute === 'tabs' ? 64 : 0 })
      .hitTestBehavior(this.mainRoute === 'tabs' ? HitTestMode.None : HitTestMode.Default)
      .visibility(this.mainRoute === 'tabs' ? Visibility.Hidden : Visibility.Visible)
    }
      .width('100%').height('100%').backgroundColor(Theme.background)
      // 试穿与偏好测验内容较长用大尺寸；其余弹层内容较短，用中尺寸避免大片空白。
      .bindSheet($$this.showSheet, this.sheetContent,
        { height: this.sheet === 'detail' ? SheetSize.MEDIUM : SheetSize.LARGE,
          showClose: true, systemMaterial: sheetMaterial(), onDisappear: () => this.onSheetClosed() })
  }

  // 底部悬浮页签 + 页面内容把
  // HdsNavigation 的标题栏是覆盖式的，内容不会自动让位，所以顶部要留出标题栏高度；
  // 底部同理要为悬浮页签留白，否则最后一行会被永久盖住 
  @Builder
  private mainTabs() {
    HdsTabs({ controller: this.tabsController, index: this.tab }) {
      ForEach(this.dockItems(), (item: DockItem, index: number) => {
        TabContent() {
          Scroll() {
            Column() {
              if (index === 0) { this.todayPage() }
              else if (index === 1) { this.wardrobePage() }
              else if (index === 2) { this.outfitPage() }
              else { this.profilePage() }
            }
              .width('100%')
              // 程序化切页签时自己做退。进场（见 switchTab 的说明）。
              // 。Dock 切页签走的是 HdsTabs 原生滑动，tabPhase 始终。1，不会叠加。
              .opacity(this.tabPhase)
              .translate({ y: this.tabPhase === 1 ? 0 : 10 })
              // 标题栏是覆盖式的：实测胶囊底边约。156vp 处，
              // 顶部留白必须大于它，否则内容会顶进标题栏被硬边切掉。
              // 底部留白 = Dock 高度 + 一点余量：barOverlap 让内容延伸到页签下方。
              // 不留白最后一行会被盖住；留太多则会空出一大块。
              // 首页已压缩为天气行，68vp 能越过胶囊下沿，避免旧天气大卡留下过多净空。
              .padding({ top: index === 0 ? 68 : Theme.titleBarClearance,
                bottom: Theme.navBarHeight + Theme.spaceL })
          }
            .height('100%')
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
        }
        .tabBar(new BottomTabBarStyle(
          { normal: new SymbolGlyphModifier(item.icon), selected: new SymbolGlyphModifier(item.selectedIcon) },
          item.label).labelStyle({
            selectedColor: Theme.accent,
            unselectedColor: Theme.tertiary
          }))
      }, (item: DockItem) => item.label)
    }
      .width('100%')
      .height('100%')
      .barPosition(BarPosition.End)
      // 允许内容延伸到页签下方，才谈得上"。在内容之上。
      .barOverlap(true)
      // 悬浮页签自带材质，系统底栏背景不再叠一层，否则胶囊会显脏。
      .barBackgroundColor(Color.Transparent)
      // 官方沉浸光感入口：悬浮页。+ 系统材质。设备不支持 IMMERSIVE 时自动降级。
      .barFloatingStyle({
        // HdsTabs 会在页签下方预留一块空白（。Dock 顶高），用小负边距压回底部。
        // 同时不压到手势条。实。-14vp 时胶囊底边距手势条约 12vp。
        barBottomMargin: -14,
        barSideMargin: Theme.spaceL,
        lightColor: Theme.accent,
        systemMaterialEffect: {
          materialType: HdsMaterialSupport.materialType(),
          materialLevel: HdsMaterialSupport.materialLevel()
        }
      })
      // 页签切换的横向过渡时长：官方 HdsTabs 自带滑动动画，这里只调快慢。
      .animationDuration(280)
      .onChange((index: number) => this.tab = index)
      .scrollable(false)
  }
}
