import { CommentItem, DEFAULT_THEME_COLOR, emojiStore } from 'data';
import { commentAvatarUrl, commentImageUrl, stripCommentHtml } from '../CommentText';
import { EmojiText } from '../EmojiText';

/**
 * 轻点判定容差与最长按住时长。
 *
 * 热评卡片位于回答底部，左右滑动必须能穿透到整页的「切换回答」手势；
 * 若直接用 onClick，滑动抬手仍会被识别为点击并打开评论页，表现为无法切换回答。
 * 因此改为原始 touch 判定，位移超容差或按住过久都不算点击。
 */
const HOT_COMMENT_TAP_SLOP_VP = 12;
const HOT_COMMENT_TAP_MAX_DURATION_MS = 300;
/** 火焰图标固定为橙红色，不跟随主题色（主题色下火焰会变成蓝色/绿色，不符合语义）。 */
const HOT_COMMENT_FLAME_COLOR: string = '#FF5722';

/**
 * 回答尾部的「热门评论」预览：最多几条由页面决定（当前 3 条，按热度排序的根评论），
 * 任一位置点击都进入该内容的完整评论页。
 *
 * 纯展示组件：数据加载、失败与空态由页面控制（无数据时不渲染本组件）。
 */
@Component
export struct HotCommentSection {
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 必须用 @Prop：数据由页面异步回填，普通成员只在首次创建时赋值，加载中会一直卡住。 */
  @Prop comments: Array<CommentItem> = [];
  @Prop totalCount: number = 0;
  @Prop loading: boolean = false;
  onOpenAll: () => void = (): void => {
  };
  /** 点击评论图片：打开全屏预览，而不是进入完整评论页。 */
  onImagePreview: (url: string) => void = (_url: string): void => {
  };
  /** 轻点判定状态：按下起点、按下时刻与是否已判为拖动。 */
  private tapDownX: number = 0;
  private tapDownY: number = 0;
  private tapDownTime: number = 0;
  private tapMoved: boolean = true;
  /** 本次手势是否起于评论图片：图片自带点击语义，卡片不能再当作「进入评论页」。 */
  private imageDownAt: number = 0;
  /** 图片轻点判定状态：按下坐标、按下时刻与是否已判为拖动。 */
  private imageDownX: number = 0;
  private imageDownY: number = 0;
  private imageTapTime: number = 0;
  private imageMoved: boolean = true;

  /** 表情表懒加载：热评正文里的 `[占位符]` 需要表情表才渲染为行内图片。 */
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      emojiStore.ensureLoaded(context);
    }
  }

  private handleTapTouch(event: TouchEvent): void {
    const touch: TouchObject | undefined = event.touches[0];
    if (touch === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.tapDownX = px2vp(touch.windowX);
      this.tapDownY = px2vp(touch.windowY);
      this.tapDownTime = Date.now();
      this.tapMoved = false;
      return;
    }
    if (event.type === TouchType.Move) {
      if (Math.abs(px2vp(touch.windowX) - this.tapDownX) > HOT_COMMENT_TAP_SLOP_VP ||
        Math.abs(px2vp(touch.windowY) - this.tapDownY) > HOT_COMMENT_TAP_SLOP_VP) {
        this.tapMoved = true;
      }
      return;
    }
    if (event.type === TouchType.Up) {
      // 抬手位置再校验一次：列表滚动接管手势后可能收不到 Move，仅凭 tapMoved 会误判为点击。
      const moved = Math.abs(px2vp(touch.windowX) - this.tapDownX) > HOT_COMMENT_TAP_SLOP_VP ||
        Math.abs(px2vp(touch.windowY) - this.tapDownY) > HOT_COMMENT_TAP_SLOP_VP;
      // 起手落在评论图片上的手势由图片自己处理（打开预览），不能同时进入完整评论页。
      const fromImage: boolean = this.imageDownAt >= this.tapDownTime;
      const isTap: boolean = !fromImage && !this.tapMoved && !moved &&
        Date.now() - this.tapDownTime <= HOT_COMMENT_TAP_MAX_DURATION_MS;
      this.tapMoved = true;
      if (isTap) {
        this.onOpenAll();
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.tapMoved = true;
    }
  }

  /**
   * 图片轻点判定：不能用 onClick，否则在同一张图片上按住后左滑切换到下一条回答时，
   * 系统仍会把这串手势当成点击打开预览，出现「既翻页又弹大图」。
   */
  private handleImageTouch(event: TouchEvent, comment: CommentItem): void {
    const touch: TouchObject | undefined = event.touches[0];
    if (touch === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.imageDownX = px2vp(touch.windowX);
      this.imageDownY = px2vp(touch.windowY);
      this.imageTapTime = Date.now();
      this.imageMoved = false;
      this.imageDownAt = this.imageTapTime;
      return;
    }
    if (event.type === TouchType.Move) {
      if (Math.abs(px2vp(touch.windowX) - this.imageDownX) > HOT_COMMENT_TAP_SLOP_VP ||
        Math.abs(px2vp(touch.windowY) - this.imageDownY) > HOT_COMMENT_TAP_SLOP_VP) {
        this.imageMoved = true;
      }
      return;
    }
    if (event.type === TouchType.Up) {
      const moved = Math.abs(px2vp(touch.windowX) - this.imageDownX) > HOT_COMMENT_TAP_SLOP_VP ||
        Math.abs(px2vp(touch.windowY) - this.imageDownY) > HOT_COMMENT_TAP_SLOP_VP;
      const isTap: boolean = !this.imageMoved && !moved &&
        Date.now() - this.imageTapTime <= HOT_COMMENT_TAP_MAX_DURATION_MS;
      this.imageMoved = true;
      if (isTap) {
        this.onImagePreview(commentImageUrl(comment.contentHtml));
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.imageMoved = true;
    }
  }

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_xsmall') }) {
        SymbolGlyph($r('sys.symbol.flame_fill'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor([HOT_COMMENT_FLAME_COLOR])
        Text('热评')
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Text(`共 ${this.totalCount} 条`)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.secondary_text')])
      }
      .id('content_detail_hot_comments_header')
      .width('100%')
      .onTouch((event: TouchEvent): void => this.handleTapTouch(event))

      if (this.loading) {
        Row({ space: $r('app.float.spacing_small') }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.resolvedThemeColor)
          Text('热评正在加载中')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .id('content_detail_hot_comments_loading')
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: $r('app.float.spacing_small'), bottom: $r('app.float.spacing_small') })
      } else if (this.comments.length === 0) {
        // 没有评论、或评论都被过滤（0 赞同不算热评）时统一提示"暂无热评"：
        // 不能再用 totalCount 推断加载失败——那会把"评论都在但都没赞"误报成接口错误。
        Text('暂无热评')
          .id('content_detail_hot_comments_empty')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: $r('app.float.spacing_small'), bottom: $r('app.float.spacing_small') })
      } else {
        ForEach(this.comments, (comment: CommentItem): void => {
          this.commentRow(comment)
        }, (comment: CommentItem): string => `hot_comment_${comment.id}`)
      }
    }
    .id('content_detail_hot_comments')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private commentRow(comment: CommentItem) {
    Row({ space: $r('app.float.spacing_small') }) {
      this.avatar(comment)
      Column({ space: $r('app.float.spacing_xsmall') }) {
        Row({ space: 6 }) {
          Text(comment.author.name.length > 0 ? comment.author.name : '知乎用户')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (comment.authorTag !== undefined && comment.authorTag.length > 0) {
            Text(comment.authorTag)
              .fontSize($r('app.float.caption_font_size'))
              .fontColor(this.resolvedThemeColor)
              .padding({ left: 4, right: 4 })
              .borderRadius(4)
              .backgroundColor($r('app.color.page_background'))
          }
          if (comment.likeCount > 0) {
            Text(`${comment.likeCount} 赞`)
              .fontSize($r('app.float.caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
        }
        .width('100%')

        EmojiText({
          text: stripCommentHtml(comment.contentHtml),
          fontSize: $r('app.float.body_font_size'),
          fontColor: $r('app.color.primary_text'),
          maxLines: 3,
          componentId: `content_detail_hot_comment_text_${comment.id}`
        })
        // 评论正文里的图片：评论页同款地址解析，热评卡片同样展示缩略图；
        // 轻点打开全屏预览（卡片本身的手势会因 imageDownAt 跳过进入评论页）。
        if (commentImageUrl(comment.contentHtml).length > 0) {
          Image(commentImageUrl(comment.contentHtml))
            .id(`content_detail_hot_comment_image_${comment.id}`)
            .width(200)
            .height(100)
            .constraintSize({ maxWidth: '100%' })
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .onTouch((event: TouchEvent): void => this.handleImageTouch(event, comment))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .onTouch((event: TouchEvent): void => this.handleTapTouch(event))
  }

  @Builder
  private avatar(comment: CommentItem) {
    if (commentAvatarUrl(comment.author.avatarUrl).length > 0) {
      Image(commentAvatarUrl(comment.author.avatarUrl))
        .width(24)
        .height(24)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
    } else {
      Text(comment.author.name.trim().length > 0 ? comment.author.name.trim().charAt(0) : '?')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(this.resolvedThemeColor)
    }
  }
}
