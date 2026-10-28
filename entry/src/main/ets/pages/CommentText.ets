/**
 * 评论文本工具：评论正文是 HTML（如 `<p>text</p>`，含表情/图片锚点），
 * 列表预览与热评卡片都需要把可见文字与图片地址拆出来。
 *
 * 评论页与回答尾部热评共用这里的实现，避免两处正则漂移。
 */

/** 评论用户头像 URL：http 归一化为 https，缺失或不受信返回空串（走首字占位）。 */
export function commentAvatarUrl(raw: string): string {
  const trimmed = raw.trim();
  const url = trimmed.startsWith('http://') ? `https://${trimmed.substring(7)}` : trimmed;
  if (!/^https:\/\/[A-Za-z0-9.-]+/.test(url)) {
    return '';
  }
  return url;
}

/** 知乎图床域名白名单：pic1/pic2/…、picx、pica 等同属 `pic*` 前缀。 */
function isZhihuImageUrl(url: string): boolean {
  return /^https:\/\/pic[a-z0-9]*\.zhimg\.com\//i.test(url);
}

/** 评论正文里的首个表情/图片地址（知乎用 `comment_img`/`comment_gif`/`comment_sticker` 锚点，
 * 表情包也常以裸 `<img>` 下发）。 */
export function commentImageUrl(html: string): string {
  const anchors = html.match(/<a\b[^>]*>/gi) ?? [];
  for (const anchor of anchors) {
    if (!/\bclass\s*=\s*["'][^"']*\bcomment_(img|gif|sticker)\b/i.test(anchor)) {
      continue;
    }
    const href = anchor.match(/\bhref\s*=\s*["']([^"']+)["']/i);
    if (href !== null) {
      const url = commentAvatarUrl(href[1].replace(/&amp;/gi, '&'));
      if (isZhihuImageUrl(url)) {
        return url;
      }
    }
  }
  const images = html.match(/<img\b[^>]*>/gi) ?? [];
  for (const image of images) {
    const src = image.match(/\bsrc\s*=\s*["']([^"']+)["']/i);
    if (src === null) {
      continue;
    }
    const url = commentAvatarUrl(src[1].replace(/&amp;/gi, '&'));
    if (isZhihuImageUrl(url)) {
      return url;
    }
  }
  return '';
}

/** 评论正文转纯文本：保留换行语义，去掉表情/图片锚点、标签与常见实体。
 * 图片统一在正文下方单独渲染，锚点内的「查看图片」字面不再保留。 */
export function stripCommentHtml(html: string): string {
  const text = html
    .replace(/<a\b[^>]*\bclass\s*=\s*["'][^"']*\bcomment_(img|gif|sticker)\b[^"']*["'][^>]*>[\s\S]*?<\/a>/gi, '')
    .replace(/<img\b[^>]*>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|blockquote)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, '\'')
    .replace(/\n{3,}/g, '\n\n');
  return text.trim();
}
