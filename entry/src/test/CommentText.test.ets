import { describe, expect, it } from '@ohos/hypium';
import { commentImageUrl, stripCommentHtml } from '../main/ets/pages/CommentText';

/** 评论正文解析：图片地址提取（含 pica 图床与裸 img 表情）与纯文本化。 */
export default function commentTextTest(): void {
  describe('commentTextTest', () => {
    it('extractsCommentImageFromPicaHostAnchor', 0, () => {
      // 知乎图床含 pica.zhimg.com（不是 pic1~pic9/picx），曾因白名单过窄取不到地址。
      const html = '这个<a href="https://pica.zhimg.com/v2-e160d8f4e19814480d181479cf56b528_qhd.jpg" ' +
        'class="comment_img" data-width="680" data-height="496">查看图片</a>';
      expect(commentImageUrl(html)).assertEqual(
        'https://pica.zhimg.com/v2-e160d8f4e19814480d181479cf56b528_qhd.jpg');
    });

    it('extractsStickerImageFromBareImgTag', 0, () => {
      const html = '<p>看这个</p><img src="https://pic4.zhimg.com/v2-sticker_l.jpg" class="comment_sticker">';
      expect(commentImageUrl(html)).assertEqual('https://pic4.zhimg.com/v2-sticker_l.jpg');
    });

    it('ignoresNonZhihuImageHosts', 0, () => {
      expect(commentImageUrl('<a href="https://evil.example.com/a.jpg" class="comment_img">查看图片</a>'))
        .assertEqual('');
      expect(commentImageUrl('<img src="https://evil.example.com/b.png">')).assertEqual('');
    });

    it('stripsImageAnchorAndKeepsVisibleText', 0, () => {
      const html = '这个<a href="https://pica.zhimg.com/v2-a.jpg" class="comment_img">查看图片</a>' +
        '<img src="https://pic4.zhimg.com/v2-b.png">[微笑]';
      expect(stripCommentHtml(html)).assertEqual('这个[微笑]');
    });

    it('keepsEmojiPlaceholdersAndBreaksLines', 0, () => {
      expect(stripCommentHtml('<p>哈哈[赞同]</p><p>第二段</p>')).assertEqual('哈哈[赞同]\n第二段');
    });
  });
}
