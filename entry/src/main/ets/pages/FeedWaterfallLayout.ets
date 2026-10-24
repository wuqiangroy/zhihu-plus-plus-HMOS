/** Shared feed breakpoint in vp, measured on the actual page container. */
export const FEED_TWO_COLUMN_MIN_WIDTH: number = 600;

/** 按较短卡片估算双列首屏容量，并预留两行供首次滑动使用。 */
export function homeFeedInitialItemTarget(width: number, height: number, topOffset: number): number {
  if (width < FEED_TWO_COLUMN_MIN_WIDTH || height <= 0) {
    return 1;
  }
  const rows: number = Math.ceil(Math.max(0, height - topOffset) / 112) + 2;
  return Math.min(60, Math.max(12, rows * 2));
}

export interface FeedFlowEntry {
  key: string;
  itemIndex: number;
  date: string;
}

export interface FeedFlowLayout {
  entries: Array<FeedFlowEntry>;
  sections: Array<SectionOptions>;
  leadingCount: number;
}

/** Full-width chrome and date headings are separate one-column sections. */
export function buildFeedFlowLayout(keys: Array<string>, dates: Array<string>, columns: number,
  leadingCount: number, loadingMore: boolean, gap: number, topOffset: number): FeedFlowLayout {
  const entries: Array<FeedFlowEntry> = [];
  const groups: Array<SectionOptions> = [];
  if (leadingCount > 0) {
    groups.push({ itemsCount: leadingCount, crossCount: 1, rowsGap: gap });
  }
  let contentCount: number = 0;
  for (let index = 0; index < keys.length; index += 1) {
    const date: string = dates[index] ?? '';
    if (date.length > 0 && (index === 0 || date !== dates[index - 1])) {
      if (contentCount > 0) {
        groups.push({ itemsCount: contentCount, crossCount: columns, columnsGap: gap, rowsGap: gap });
        contentCount = 0;
      }
      entries.push({ key: `date:${date}`, itemIndex: index, date: date });
      groups.push({ itemsCount: 1, crossCount: 1 });
    }
    entries.push({ key: keys[index], itemIndex: index, date: '' });
    contentCount += 1;
  }
  if (contentCount > 0) {
    groups.push({ itemsCount: contentCount, crossCount: columns, columnsGap: gap, rowsGap: gap });
  }
  if (loadingMore) {
    groups.push({ itemsCount: 1, crossCount: 1 });
  }
  for (let index = 0; index < groups.length; index += 1) {
    groups[index].margin = { top: index === 0 ? topOffset : gap };
  }
  return { entries: entries, sections: groups, leadingCount: leadingCount };
}

/** Translate a visible FlowItem to its source index, excluding banners and footer. */
export function feedFlowItemIndex(layout: FeedFlowLayout, flowIndex: number): number {
  const index: number = flowIndex - layout.leadingCount;
  if (index < 0 || layout.entries.length === 0) {
    return -1;
  }
  return layout.entries[Math.min(index, layout.entries.length - 1)].itemIndex;
}
