import { resourceManager } from '@kit.LocalizationKit';
import { AppThemeMode } from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/** 状态栏内容色（时间/电量）：深色背景用白字，浅色背景用黑字。 */
function statusBarContentColor(isDark: boolean): string {
  return isDark ? '#FFFFFF' : '#000000';
}

/**
 * 按当前主题应用状态栏内容色，并把结果广播到 AppStorage。
 *
 * HdsNavigation/NavDestination 的 systemBarStyle 读同一份广播值：导航转场时由系统按
 * 栈顶页面统一应用并还原，不会再出现详情页退出后图标色停留在白色的问题。窗口级写入
 * 只负责首帧与主题切换，两边取值同一来源，避免互相覆盖。
 */
export function updateStatusBarAppearance(systemIsDark?: boolean): void {
  const context = getAbilityContext();
  const mode = AppStorage.get<AppThemeMode>('appThemeMode') ?? AppThemeMode.SYSTEM;
  let configDark = false;
  try {
    configDark = context?.resourceManager.getConfigurationSync().colorMode ===
      resourceManager.ColorMode.DARK;
  } catch (_error) {
  }
  const isDark = mode === AppThemeMode.DARK || (mode === AppThemeMode.SYSTEM &&
    (systemIsDark ?? configDark));
  AppStorage.setOrCreate('systemBarContentColor', statusBarContentColor(isDark));
  if (context === undefined) {
    return;
  }
  try {
    const mainWindow = context.windowStage?.getMainWindowSync();
    if (mainWindow === undefined) {
      return;
    }
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      // 新老字段同时给：部分系统版本只认 isStatusBarLightIcon（true=白色图标）。
      isStatusBarLightIcon: isDark,
      statusBarContentColor: statusBarContentColor(isDark)
    }).catch((_error: Object): void => {
    });
  } catch (_error) {
  }
}

/** 当前状态栏可见性（模块级）：仅在真正需要切换时调用系统接口。 */
let statusBarHiddenNow: boolean = false;

/**
 * 隐藏/恢复状态栏（对齐上游 ArticleImmersiveModeEffect：沉浸式真全屏，只藏 statusBars）。
 * 隐藏后 TYPE_SYSTEM 避让区归零，avoidAreaChange 监听会把 statusBarHeight 刷成 0，
 * 页面顶部留空随之收起；恢复时反向还原。
 *
 * 注意：setWindowSystemBarEnable 会把状态栏内容色重置为系统默认（白）。普通页面反复
 * 进入详情都会调用本函数恢复状态栏，若每次都调用系统接口，浅色页面的时间/电量就会变成白色。
 * 因此与当前状态相同直接跳过；真正恢复显示后再按主题重新应用内容色。
 */
export function setStatusBarHidden(hidden: boolean): void {
  if (hidden === statusBarHiddenNow) {
    return;
  }
  const context = getAbilityContext();
  try {
    const mainWindow = context?.windowStage?.getMainWindowSync();
    if (mainWindow === undefined) {
      return;
    }
    statusBarHiddenNow = hidden;
    mainWindow.setWindowSystemBarEnable(hidden ? ['navigation'] : ['status', 'navigation'])
      .then((): void => {
        // 重新启用状态栏会把内容色重置为系统默认（白），恢复显示后必须按主题重新应用，
        // 否则浅色页面上时间/电量会变成白色不可见。系统侧的重置晚于 Promise 落地，
        // 因此紧随其后补一次，再延后一次兜底。
        if (!hidden) {
          updateStatusBarAppearance();
          setTimeout((): void => updateStatusBarAppearance(), 150);
        }
      })
      .catch((_error: Error): void => {
      });
  } catch (_error) {
  }
}
