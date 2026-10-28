import { CommentItem } from 'data';
import { commentImageUrl, stripCommentHtml } from './CommentText';

/** 回答尾部「热门评论」展示条数上限。 */
export const HOT_COMMENT_PREVIEW_LIMIT: number = 3;

/**
 * 从热度排序的根评论页里挑出适合在回答尾部预览的条目：
 * 去掉已折叠、已删除、没有任何可见文字/图片、以及赞同数为 0 的评论，按服务端顺序取前 limit 条。
 */
export function hotCommentPreview(items: Array<CommentItem>, limit: number): Array<CommentItem> {
  const picked: Array<CommentItem> = [];
  if (limit <= 0) {
    return picked;
  }
  for (const item of items) {
    if (picked.length >= limit) {
      break;
    }
    if (item.isDelete || item.collapsed) {
      continue;
    }
    // 0 赞同的评论不算"热评"：热度排序兜底段会混入没人认可的条目，预览里直接跳过。
    if (item.likeCount <= 0) {
      continue;
    }
    if (stripCommentHtml(item.contentHtml).length === 0 && commentImageUrl(item.contentHtml).length === 0) {
      continue;
    }
    picked.push(item);
  }
  return picked;
}
