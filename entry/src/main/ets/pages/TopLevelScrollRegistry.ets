/**
 * 顶级页签滚动容器登记表。
 *
 * HdsNavigation 需要经 `bindToScrollable` 绑定可滚动容器，才知道内容区的滚动偏移，
 * 进而驱动标题栏的滚动模糊（华为官方「HdsNavigation 嵌套 HdsTabs 滚动模糊丢失」
 * 解决方案口径）。各页签页各自持有 Scroller，这里统一登记，AppShell 取快照后
 * 传给 `bindToScrollable`。
 */
export class TopLevelScrollRegistry {
  private readonly scrollers: Array<Scroller> = [];

  /** 登记页签页的滚动容器；重复登记同一实例不重复入表。 */
  register(scroller: Scroller): void {
    if (this.scrollers.indexOf(scroller) >= 0) {
      return;
    }
    this.scrollers.push(scroller);
    // 跨组件通信走 AppStorage 广播（@Provide/@Consume 在 HdsTabs 树下实测不链接）。
    AppStorage.setOrCreate('topLevelScrollableTick', (AppStorage.get<number>('topLevelScrollableTick') ?? 0) + 1);
  }

  snapshot(): Array<Scroller> {
    return this.scrollers.slice(0);
  }
}

export const topLevelScrollRegistry: TopLevelScrollRegistry = new TopLevelScrollRegistry();
