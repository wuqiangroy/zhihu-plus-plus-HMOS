import { Answer, Article, Question } from '../domain/DomainModels';
import {
  decodeAnswerDetail,
  decodeArticleDetail,
  decodeQuestionDetail
} from '../domain/ContentDetailDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { ContentDetailKind, ContentRepository } from './ContentRepository';

export const QUESTION_DETAIL_INCLUDE =
  'read_count,visit_count,answer_count,voteup_count,comment_count,follower_count,detail,excerpt,author,' +
    'relationship.is_following,topics';
export const ANSWER_DETAIL_INCLUDE =
  '.settings,content,editable_content,paid_info,can_comment,excerpt,thanks_count,voteup_count,comment_count,' +
    'visited_count,attachment,reaction,ip_info,pagination_info,endorsements,question.title,question.topics,' +
    'reaction.relation.voting,author.badge_v2,settings.table_of_contents.enabled,segment_infos,allow_segment_interaction';
export const ARTICLE_DETAIL_INCLUDE =
  'content,topics,paid_info,can_comment,excerpt,thanks_count,voteup_count,comment_count,visited_count,' +
    'relationship,ip_info,relationship.vote,author.badge_v2,segment_infos';

export enum ContentRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class ContentRepositoryFailure extends Error {
  readonly kind: ContentRepositoryFailureKind;

  constructor(kind: ContentRepositoryFailureKind) {
    super(kind === ContentRepositoryFailureKind.INVALID_ID ? '内容 ID 无效' : '内容详情请求已取消');
    this.name = 'ContentRepositoryFailure';
    this.kind = kind;
  }
}

export function normalizeContentId(id: string): string {
  if (!/^[1-9][0-9]{0,29}$/.test(id)) {
    throw new ContentRepositoryFailure(ContentRepositoryFailureKind.INVALID_ID);
  }
  return id;
}

export function buildContentDetailUrl(kind: ContentDetailKind, id: string): string {
  const normalizedId = normalizeContentId(id);
  let collection: string;
  let include: string;
  switch (kind) {
    case ContentDetailKind.QUESTION:
      collection = 'questions';
      include = QUESTION_DETAIL_INCLUDE;
      break;
    case ContentDetailKind.ANSWER:
      collection = 'answers';
      include = ANSWER_DETAIL_INCLUDE;
      break;
    case ContentDetailKind.ARTICLE:
      collection = 'articles';
      include = ARTICLE_DETAIL_INCLUDE;
      break;
  }
  return `https://www.zhihu.com/api/v4/${collection}/${normalizedId}?include=${encodeURIComponent(include)}`;
}

export class DefaultContentRepository implements ContentRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;
  private readonly answerCacheSize: number;
  /** 回答正文 LRU 缓存：切换回答时命中预取结果，避免整页重新加载。 */
  private readonly answerCache: Map<string, Answer> = new Map<string, Answer>();
  /** 同一回答的在飞请求：预取与切换复用同一 promise，避免单飞冲突（BUSY）。 */
  private readonly answering: Map<string, Promise<Answer>> = new Map<string, Promise<Answer>>();

  constructor(httpClient: ZhihuHttpClient, answerCacheSize: number = 0) {
    this.httpClient = httpClient;
    this.answerCacheSize = answerCacheSize > 0 ? answerCacheSize : 0;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getQuestion(id: string): Promise<Question> {
    const normalizedId = normalizeContentId(id);
    const response = await this.fetch(ContentDetailKind.QUESTION, normalizedId);
    return decodeQuestionDetail(response.body, normalizedId);
  }

  async getAnswer(id: string, preferCache: boolean = false): Promise<Answer> {
    const normalizedId = normalizeContentId(id);
    if (preferCache && this.answerCacheSize > 0) {
      const cached = this.answerCache.get(normalizedId);
      if (cached !== undefined) {
        this.touchAnswerCache(normalizedId, cached);
        return cached;
      }
    }
    const inflight = this.answering.get(normalizedId);
    if (inflight !== undefined) {
      return inflight;
    }
    const task = this.fetchAnswer(normalizedId);
    this.answering.set(normalizedId, task);
    try {
      const answer = await task;
      if (this.answerCacheSize > 0) {
        this.touchAnswerCache(normalizedId, answer);
      }
      return answer;
    } finally {
      this.answering.delete(normalizedId);
    }
  }

  private async fetchAnswer(normalizedId: string): Promise<Answer> {
    const response = await this.fetch(ContentDetailKind.ANSWER, normalizedId);
    return decodeAnswerDetail(response.body, normalizedId);
  }

  /** LRU 写入：重新插入保证顺序，超限淘汰最久未使用的一条。 */
  private touchAnswerCache(id: string, answer: Answer): void {
    this.answerCache.delete(id);
    this.answerCache.set(id, answer);
    if (this.answerCache.size <= this.answerCacheSize) {
      return;
    }
    const oldest = this.answerCache.keys().next();
    if (!oldest.done) {
      this.answerCache.delete(oldest.value);
    }
  }

  async getArticle(id: string): Promise<Article> {
    const normalizedId = normalizeContentId(id);
    const response = await this.fetch(ContentDetailKind.ARTICLE, normalizedId);
    return decodeArticleDetail(response.body, normalizedId);
  }

  private async fetch(kind: ContentDetailKind, id: string): Promise<ZhihuHttpResponse> {
    const requestGeneration = this.generation;
    const response = await this.httpClient.execute({
      url: buildContentDetailUrl(kind, id),
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new ContentRepositoryFailure(ContentRepositoryFailureKind.CANCELLED);
    }
    return response;
  }
}
