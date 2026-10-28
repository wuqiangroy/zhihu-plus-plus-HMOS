import { Answer, Article, Question } from '../domain/DomainModels';

export enum ContentDetailKind {
  QUESTION = 'question',
  ANSWER = 'answer',
  ARTICLE = 'article'
}

export interface ContentRepository {
  getQuestion(id: string): Promise<Question>;
  /**
   * 读取回答正文。preferCache 为 true 时优先复用上一次拉取的结果（回答切换导航命中预取），
   * 缺省 false 表示必须拿到网络最新数据（下拉刷新等场景）。
   */
  getAnswer(id: string, preferCache?: boolean): Promise<Answer>;
  getArticle(id: string): Promise<Article>;
  cancel(): void;
}
