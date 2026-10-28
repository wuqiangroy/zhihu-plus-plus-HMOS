/** PR112 behavior gates. Runs real ArkTS classes/methods with platform IO replaced.
 * node scripts/test-pr112-restoration.cjs --typescript <typescript module path>
 * --baseline only accepts the explicitly recorded defects; it is NOT a passing acceptance run.
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const typeScriptArg = args.indexOf('--typescript');
const ts = require(typeScriptArg >= 0 ? path.resolve(args[typeScriptArg + 1]) : 'typescript');
const baseline = args.includes('--baseline');
const cache = new Map();
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
}).outputText;
function load(file) {
  const full = path.resolve(root, file);
  if (cache.has(full)) return cache.get(full).exports;
  const mod = { exports: {} };
  cache.set(full, mod);
  const localRequire = spec => {
    if (spec === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    if (spec.startsWith('@kit.')) return {};
    if (spec.endsWith('/CookieSession')) return { toCookieHeader: () => 'd_c0=test' };
    if (spec.endsWith('/ZhihuFetchSignature')) return { createZse96Header: () => 'test', ZHIHU_WEB_ZSE93: 'test' };
    if (spec.endsWith('/ContentDetailDecoder')) return {
      decodeAnswerDetail: JSON.parse, decodeArticleDetail: JSON.parse, decodeQuestionDetail: JSON.parse
    };
    if (spec.endsWith('/DomainModels')) return {};
    if (spec === 'data') return {
      ...load('data/src/main/ets/repository/ContentRepository.ets'),
      ...load('data/src/main/ets/repository/DefaultContentRepository.ets'),
      ...load('data/src/main/ets/network/HttpFailure.ets'),
      QuestionAnswerSortOrder: { DEFAULT: 'default' },
      DomainDecodeError: class DomainDecodeError extends Error {}
    };
    return load(path.relative(root, path.resolve(path.dirname(full), spec + '.ets')));
  };
  vm.runInThisContext('(function(require,module,exports){' + compile(read(file)) + '\n})',
    { filename: full })(localRequire, mod, mod.exports);
  return mod.exports;
}
function methodHarness(file, name, globals = {}) {
  const source = read(file);
  const begin = source.search(new RegExp('  private (?:async )?' + name + '\\('));
  assert(begin >= 0, `method missing: ${name}`);
  const end = source.indexOf('\n  }', begin);
  assert(end > begin, `method end missing: ${name}`);
  return vm.runInNewContext(compile('class Harness {\n' + source.slice(begin, end + 4) + '\n}') + '\nHarness', globals);
}
const pages = 'entry/src/main/ets/pages/';
const { ContentDetailController } = load(pages + 'ContentDetailState.ets');
const { ContentDetailKind } = load('data/src/main/ets/repository/ContentRepository.ets');
const answer = id => ({id, questionId: '123', contentHtml: '<p>body</p>', excerpt: '', url: '',
  voteupCount: 0, commentCount: 0, createdAt: 1, updatedAt: 1});
const tests = [];
function contract(name, expectedDefect, run) { tests.push({name, expectedDefect, run}); }
function controllerFixture() {
  const repository = {fail: false, getAnswer: async id => {
    if (repository.fail) throw Error('network');
    return answer(id);
  }, cancel() {}};
  const controller = new ContentDetailController(repository);
  controller.activate();
  return {controller, repository};
}
contract('target-failure-keeps-current-body-and-identity', true, async () => {
  const {controller, repository} = controllerFixture();
  await controller.load(ContentDetailKind.ANSWER, '1');
  repository.fail = true;
  const Harness = methodHarness(pages + 'ContentDetailPages.ets', 'applyAnswerMove', {
    AppStorage: {setOrCreate() {}}, ContentDetailKind
  });
  const page = new Harness();
  Object.assign(page, {answerNavigator: {previousAnswerPreview() {}, nextAnswerPreview() {},
    move: async () => '2'}, navigatorRevision: 0, pageActive: true, activeContentId: '1', controller,
    publishPreviewAnswerTitle() {}, getUIContext: () => ({getPromptAction: () => ({showToast() {}})})});
  const moved = await page.applyAnswerMove(1);
  try {
    assert.equal(moved, false, 'failed target must report failure');
    assert.equal(page.activeContentId, '1');
    assert.equal(controller.snapshot().phase, 'ready');
    assert.equal(controller.snapshot().content.value.id, '1');
  } finally { controller.deactivate(); }
});
contract('prepare-failure-keeps-current-document', true, async () => {
  const {controller, repository} = controllerFixture();
  try {
    await controller.load(ContentDetailKind.ANSWER, '1');
    const original = controller.snapshot().content;
    assert.equal(typeof controller.prepareAnswer, 'function', 'restore preparation API');
    repository.fail = true;
    assert.equal(await controller.prepareAnswer('2'), undefined);
    assert.deepEqual(controller.snapshot().content, original);
    assert.equal(controller.snapshot().phase, 'ready');
  } finally { controller.deactivate(); }
});
contract('candidate-commits-once-and-rejects-stale-candidate', true, async () => {
  const {controller} = controllerFixture();
  try {
    await controller.load(ContentDetailKind.ANSWER, '1');
    assert.equal(typeof controller.admitAnswer, 'function', 'restore admission API');
    const stale = controller.admitAnswer(answer('2'));
    const next = controller.admitAnswer(answer('3'));
    assert(stale && next);
    assert.equal(controller.commitPreparedAnswer(stale), false);
    assert.equal(controller.snapshot().content.value.id, '1');
    assert.equal(controller.commitPreparedAnswer(next), true);
    assert.equal(controller.commitPreparedAnswer(next), false);
    const departed = controller.admitAnswer(answer('4'));
    controller.deactivate(); controller.activate();
    assert.equal(controller.commitPreparedAnswer(departed), false);
  } finally { controller.deactivate(); }
});
contract('non-entry-answer-restores-its-own-position', true, () => {
  const saved = {blockIndex: 4, fraction: 0.5};
  const keys = [];
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', 'prepareReaderPosition', {
    getAbilityContext: () => ({}), createReaderPositionStore: () => ({load: key => {keys.push(key); return saved;}}),
    readerPositionBlockIndex: () => 4
  });
  const document = new Harness();
  Object.assign(document, {positionIsActive: () => true, readingLayout: true, empty: false,
    positionKey: 'answer:2', positionOwnerKey: 'answer:1', blocks: []});
  document.prepareReaderPosition();
  assert.deepEqual(keys, ['answer:2']);
  assert.equal(document.pendingPosition, saved);
  assert.equal(document.positionWritable, false, 'do not overwrite saved progress before restoration');
});
contract('independent-prefetch-does-not-block-foreground', true, async () => {
  const {ZhihuHttpClient} = load('data/src/main/ets/network/ZhihuHttpClient.ets');
  const {DefaultContentRepository} = load('data/src/main/ets/repository/DefaultContentRepository.ets');
  // Use Index's actual repository wiring: shared on PR, isolated after factory restoration.
  const index = read(pages + 'Index.ets');
  let finish;
  const cookies = {getCookies: () => [{name: 'd_c0', value: 'test'}]};
  // Execute the actual repository construction statements, not a hand-written alternative wiring.
  const foregroundStatement = index.match(/this\.answerRepository = new DefaultContentRepository[^;]+;/)?.[0];
  assert(foregroundStatement, 'Index answer repository wiring missing');
  const factoryStatement = index.match(/this\.answerPrefetchRepositoryFactory = \(\): ContentRepository =>[\s\S]*?;/)?.[0] ?? '';
  let requestCount = 0;
  class HarnessClient extends ZhihuHttpClient {
    constructor(session) {
      super(session, {create: () => ({request: () => {
        requestCount++;
        if (requestCount === 1) return new Promise(resolve => {finish = resolve;});
        return Promise.resolve({statusCode: 200, body: JSON.stringify(answer('1'))});
      }, destroy() {}})});
    }
  }
  const Wiring = vm.runInNewContext(compile('class Wiring { constructor() {' +
    foregroundStatement + factoryStatement + '} }') + '\nWiring',
    {DefaultContentRepository, ZhihuHttpClient: HarnessClient, session: cookies});
  const wiring = new Wiring();
  const foreground = wiring.answerRepository;
  const background = wiring.answerPrefetchRepositoryFactory?.() ?? foreground;
  const pending = background.getAnswer('2', true);
  // Handle rejection immediately so a failed assertion never leaves an unhandled promise.
  const result = foreground.getAnswer('1').then(value => ({value}), error => ({error}));
  await Promise.resolve();
  finish({statusCode: 200, body: JSON.stringify(answer('2'))});
  await pending;
  const response = await result;
  assert.equal(response.error, undefined, 'foreground must not fail BUSY while neighbor is fetching');
  assert.equal(response.value.id, '1');
});
contract('navigation-prepare-and-peek-do-not-advance-or-fetch', true, async () => {
  const {QuestionAnswerNavigator} = load(pages + 'QuestionAnswerNavigator.ets');
  let calls = 0;
  const seed = {phase: 'ready', items: ['1', '2'].map(id => ({feedItem: {target: answer(id)}})),
    loadingMore: false, canLoadMore: true, sortOrder: 'default', errorMessage: '', requiresLogin: false, nextCursor: 'next'};
  const navigator = new QuestionAnswerNavigator('123', '1', seed, {cancel() {}, getPage: async () => {calls++; throw Error('unexpected paging');}});
  try {
    assert.equal(typeof navigator.prepareMove, 'function', 'restore navigation preparation');
    assert.equal(await navigator.prepareMove(1), '2');
    assert.equal(navigator.currentId(), '1');
    assert.equal(navigator.peekId(1), '2');
    assert.equal(navigator.peekId(-1), undefined);
    assert.equal(calls, 0);
  } finally { navigator.dispose(); }
});
contract('prefetch-queue-deduplicates-prioritizes-and-drops-late-results', true, async () => {
  const file = pages + 'AnswerSwitchPrefetch.ets';
  assert(fs.existsSync(path.join(root, file)), 'restore independent prefetcher');
  const {AnswerDetailPrefetcher, ANSWER_PREFETCH_CAPACITY} = load(file);
  const requests = [], pending = [];
  let cancelled = 0;
  const repository = {getAnswer: id => {requests.push(id); return new Promise((resolve, reject) =>
    pending.push({id, resolve, reject}));}, cancel() {cancelled++;}};
  const prefetcher = new AnswerDetailPrefetcher(repository);
  const tick = () => new Promise(resolve => setTimeout(resolve, 0));
  const resolveNext = () => {const item = pending.shift(); item.resolve(answer(item.id));};
  try {
    const first = prefetcher.request('2', false);
    const duplicate = prefetcher.request('2', false);
    const behind = prefetcher.request('3', false);
    await tick();
    assert.deepEqual(requests, ['2']);
    const foreground = prefetcher.request('4', true);
    resolveNext(); await tick();
    assert.deepEqual(requests, ['2', '4']);
    resolveNext(); await tick(); resolveNext();
    assert.equal((await first).id, '2'); assert.equal((await duplicate).id, '2');
    assert.equal((await foreground).id, '4'); assert.equal((await behind).id, '3');
    for (let i = 5; i < 5 + ANSWER_PREFETCH_CAPACITY; i++) {
      const task = prefetcher.request(String(i), false); await tick(); resolveNext(); await task;
    }
    assert.equal(prefetcher.cacheSize(), ANSWER_PREFETCH_CAPACITY);
    assert.equal(prefetcher.peek('2'), undefined);
    const failed = prefetcher.request('99', false); await tick(); pending.shift().reject(Error('network'));
    assert.equal(await failed, undefined); assert.equal(prefetcher.peek('99'), undefined);
    const late = prefetcher.request('100', false); await tick(); prefetcher.reset(); resolveNext();
    assert.equal(await late, undefined); assert.equal(prefetcher.cacheSize(), 0); assert(cancelled > 0);
    prefetcher.dispose(); prefetcher.dispose();
    assert.equal(await prefetcher.request('101', true), undefined);
  } finally { prefetcher.dispose(); }
});
contract('cancelled-candidate-does-not-write-progress', true, () => {
  let writes = 0;
  const saved = {blockIndex: 4, fraction: 0.5};
  const store = {load: () => saved, save: () => {writes++;}};
  const prepare = methodHarness(pages + 'NativeContentDocument.ets', 'prepareReaderPosition', {
    getAbilityContext: () => ({}), createReaderPositionStore: () => store, readerPositionBlockIndex: () => 4
  });
  const persist = methodHarness(pages + 'NativeContentDocument.ets', 'persistReaderPosition', {clearTimeout() {}});
  const document = new prepare();
  Object.assign(document, {positionIsActive: () => false, readingLayout: true, empty: false,
    positionKey: 'answer:2', positionOwnerKey: 'answer:1', blocks: [], positionSaveTimer: -1,
    captureReaderPosition: () => ({blockIndex: -1, fraction: 0})});
  document.prepareReaderPosition();
  persist.prototype.persistReaderPosition.call(document, true);
  assert.equal(writes, 0, 'candidate disposal must not overwrite target progress');
});
contract('name-resources-and-share-fallback-match-main', false, () => {
  for (const [file, key, value] of [
    ['AppScope/resources/base/element/string.json', 'app_name', '知乎++鸿蒙版'],
    ['entry/src/main/resources/base/element/string.json', 'EntryAbility_label', '知乎++鸿蒙版'],
    ['entry/src/main/resources/en_US/element/string.json', 'EntryAbility_label', 'Zhihu++HMOS']]) {
    assert.equal(JSON.parse(read(file)).string.find(item => item.name === key).value, value);
  }
  for (const name of ['AppShell', 'SystemUpdateSettingsPage']) {
    assert(read(pages + name + '.ets').includes("Text($r('app.string.EntryAbility_label'))"), name + ' must use localized resource');
  }
  const update = read(pages + 'SystemUpdateSettingsPage.ets');
  assert(update.includes("context.resourceManager.getStringSync($r('app.string.EntryAbility_label').id)"));
  assert(!update.includes('知乎++鸿蒙版'), 'download text must use resource too');
  for (const name of ['AppShell', 'SystemUpdateSettingsPage', 'ContentDetailPages', 'NativeContentDocument', 'PeoplePinDetailPages']) {
    assert(!read(pages + name + '.ets').includes('知乎Plus'), name);
  }
});
(async () => {
  let failed = 0;
  for (const item of tests) {
    try {
      await item.run();
      console.log('PASS ' + item.name);
      if (baseline && item.expectedDefect) { failed++; console.error('Baseline changed: remove resolved defect from expected list'); }
    } catch (error) {
      // Runtime/fixture errors are never accepted as a known regression.
      const known = baseline && item.expectedDefect && error.code === 'ERR_ASSERTION';
      console.log((known ? 'KNOWN-FAIL ' : 'FAIL ') + item.name + ': ' + error.message);
      if (!known) failed++;
    }
  }
  console.log(baseline ? 'Baseline capture only; KNOWN-FAIL cases are unresolved acceptance gates.' : 'Acceptance run (all contracts must pass).');
  process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
