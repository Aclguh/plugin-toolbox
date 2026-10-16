import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试统一锚定的发布标签（生产禁用分支名，规避 jsDelivr 分支强缓存）
const testRef = 'v1.0.0';

/// 记录请求并按注册的响应回放的测试用 HTTP 客户端。
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  final List<String> requestedUrls = [];

  int get requestCount => requestedUrls.length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url.toString());
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

http.Response jsonResponse(Object payload, {int status = 200}) =>
    http.Response(json.encode(payload), status, headers: {
      'content-type': 'application/json; charset=utf-8',
    });

Map<String, dynamic> flatFile(String name, {required String hash, int? size}) =>
    {
      'name': name,
      'hash': hash,
      'size': size ?? 100,
    };

/// 计算 jsDelivr 清单接口风格的内容哈希（SHA-256 的 base64）
String jsDelivrHashOf(List<int> bytes) =>
    base64.encode(sha256.convert(bytes).bytes);

/// 假 CDN 固定使用的安装包字节（ZIP 含打包时间戳，逐次构建字节会漂移，
/// 而清单哈希必须稳定对应一份字节，因此整组测试共享同一份预构建产物）
final Uint8List fakePtxBytes = buildPtx(id: 'base64_tool', version: '1.1.0');

Map<String, dynamic> flatListing() => {
      'default': 'master',
      'files': [
        {'name': '/.gitignore', 'hash': 'h_gitignore', 'size': 20},
        {'name': '/README.md', 'hash': 'h_readme', 'size': 500},
        // 正常插件: 清单 + 安装包齐备
        {
          'name': '/plugin-source/base64_tool/plugin.json',
          'hash': 'h_b64_manifest',
          'size': 355
        },
        {
          'name': '/plugin-source/base64_tool/main.lua',
          'hash': 'h_b64_lua',
          'size': 900
        },
        // dist 产物哈希按真实字节计算, 使目录条目可通过下载完整性校验
        {
          'name': '/dist/base64_tool.ptx',
          'hash': jsDelivrHashOf(fakePtxBytes),
          'size': 2246
        },
        // 目录名与清单 id 不一致的脏数据, 应被跳过
        {
          'name': '/plugin-source/broken_tool/plugin.json',
          'hash': 'h_broken',
          'size': 100
        },
        // 尚未打包: 有清单没有产物, 但仍应出现在目录中(安装按钮给出缺失提示)
        {
          'name': '/plugin-source/unpacked_tool/plugin.json',
          'hash': 'h_unpacked',
          'size': 120
        },
        // 嵌套目录不应被误认为插件目录
        {
          'name': '/plugin-source/base64_tool/ui/main.ui.json',
          'hash': 'h_b64_ui',
          'size': 400
        },
      ],
    };

const _base64Manifest = '''
{
  "id": "base64_tool",
  "name": "Base64 编解码",
  "version": "1.1.0",
  "description": "Base64 文本编码与解码转换工具",
  "author": "PluginToolbox Team",
  "minAppVersion": "0.1.0",
  "category": "encoding",
  "permissions": ["clipboard"],
  "entry": "main.lua",
  "ui": "ui/main.ui.json"
}
''';

const _unpackedManifest = '''
{
  "id": "unpacked_tool",
  "name": "未打包插件",
  "version": "0.9.0",
  "description": "只有源码尚未打包",
  "author": "PluginToolbox Team",
  "category": "text",
  "permissions": [],
  "entry": "main.lua",
  "ui": "ui/main.ui.json"
}
''';

/// 构造覆盖"正常 + 脏数据 + 缺产物"的假 CDN。
FakeHttpClient buildFakeCdn({bool rateLimited = false, bool offline = false}) {
  return FakeHttpClient((request) async {
    if (offline) {
      throw http.ClientException('connection refused');
    }
    if (rateLimited) {
      return http.Response('{"message":"too many requests"}', 429);
    }
    final url = request.url.toString();
    if (url.contains('data.jsdelivr.com')) {
      return jsonResponse(flatListing());
    }
    if (url.endsWith('/plugin-source/base64_tool/plugin.json')) {
      return http.Response(_base64Manifest, 200,
          headers: {'content-type': 'application/json'});
    }
    if (url.endsWith('/plugin-source/unpacked_tool/plugin.json')) {
      return http.Response(_unpackedManifest, 200,
          headers: {'content-type': 'application/json'});
    }
    if (url.endsWith('/plugin-source/broken_tool/plugin.json')) {
      // 清单 id 与目录名不一致
      return http.Response('{"id":"other_tool","name":"Broken"}', 200);
    }
    if (url.endsWith('/dist/base64_tool.ptx')) {
      return http.Response.bytes(
        fakePtxBytes,
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  });
}

/// 构造一个内容合法的 .ptx (ZIP)
Uint8List buildPtx({
  String id = 'base64_tool',
  String version = '1.1.0',
  String entry = 'main.lua',
  String ui = 'ui/main.ui.json',
  bool includeEntry = true,
  bool includeUi = true,
}) {
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'plugin.json',
    json.encode({
      'id': id,
      'name': 'Base64 编解码',
      'version': version,
      'description': 'd',
      'author': 'a',
      'type': 'lua',
      'category': 'encoding',
      'permissions': ['clipboard'],
      'entry': entry,
      'ui': ui,
    }),
  );
  if (includeEntry) add(entry, 'return nil');
  if (includeUi) add(ui, '{"type":"Column","children":[]}');
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

PluginStoreEntry entryWith({
  String id = 'base64_tool',
  String? packageUrl,
  String? packageHash,
}) =>
    PluginStoreEntry(
      id: id,
      name: 'Base64 编解码',
      version: '1.1.0',
      description: 'd',
      author: 'a',
      category: 'encoding',
      permissions: const [],
      packageName: '$id.ptx',
      packageSizeBytes: 20,
      packageHash: packageHash,
      packageUrl: packageUrl,
      manifestApiUrl: 'https://cdn.jsdelivr.net/x/plugin.json',
      sourcePath: 'plugin-source/$id',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PluginStoreSemantics 版本比较与安装态判定', () {
    test('标准三段的版本号比较', () {
      expect(PluginStoreSemantics.compareVersions('1.2.3', '1.2.3'), 0);
      expect(PluginStoreSemantics.compareVersions('1.2.4', '1.2.3'),
          greaterThan(0));
      expect(
          PluginStoreSemantics.compareVersions('1.2.3', '1.3.0'), lessThan(0));
      expect(PluginStoreSemantics.compareVersions('2.0.0', '1.9.9'),
          greaterThan(0));
    });

    test('缺失段补零、允许 v 前缀与构建号/预发布后缀', () {
      expect(PluginStoreSemantics.compareVersions('1.2', '1.2.0'), 0);
      expect(PluginStoreSemantics.compareVersions('v1.2.0', '1.2.0'), 0);
      expect(PluginStoreSemantics.compareVersions('1.2.0+3', '1.2.0'), 0);
      expect(PluginStoreSemantics.compareVersions('1.2.0-beta.1', '1.2.0'), 0);
    });

    test('无法解析的脏版本号按 0 处理而不抛错', () {
      expect(PluginStoreSemantics.compareVersions('not-a-version', '0.0.1'),
          lessThan(0));
      // `1a` 整段非数字 -> 归零, 因此 1a.2.3 视为 0.2.3
      expect(
          PluginStoreSemantics.compareVersions('1a.2.3', '0.2.4'), lessThan(0));
      expect(PluginStoreSemantics.compareVersions('1a.2.3', '0.2.3'), 0);
      expect(PluginStoreSemantics.compareVersions('', '1.0.0'), lessThan(0));
    });

    PluginManifest manifest(String id, String version) => PluginManifest(
          id: id,
          name: id,
          version: version,
          description: '',
          author: 'tester',
          type: 'lua',
          category: PluginCategory.other,
          permissions: const [],
          entry: 'main.lua',
          ui: 'ui/main.ui.json',
        );

    test('resolveState 区分未安装 / 可更新 / 已是最新', () {
      final installed = [
        manifest('base64_tool', '1.0.0'),
        manifest('hash_tool', '1.1.0')
      ];

      expect(
        PluginStoreSemantics.resolveState(
          pluginId: 'base64_tool',
          storeVersion: '1.1.0',
          installedManifests: installed,
        ),
        PluginStoreInstallState.updateAvailable,
      );
      expect(
        PluginStoreSemantics.resolveState(
          pluginId: 'hash_tool',
          storeVersion: '1.1.0',
          installedManifests: installed,
        ),
        PluginStoreInstallState.upToDate,
      );
      expect(
        PluginStoreSemantics.resolveState(
          pluginId: 'qr_tool',
          storeVersion: '1.1.0',
          installedManifests: installed,
        ),
        PluginStoreInstallState.notInstalled,
      );
    });

    test('本地版本高于商店版本时不提示降级为"可更新"', () {
      expect(
        PluginStoreSemantics.resolveState(
          pluginId: 'base64_tool',
          storeVersion: '1.0.0',
          installedManifests: [manifest('base64_tool', '1.2.0')],
        ),
        PluginStoreInstallState.upToDate,
      );
    });

    test('needsDownload 只对未安装与可更新为真', () {
      expect(PluginStoreInstallState.notInstalled.needsDownload, isTrue);
      expect(PluginStoreInstallState.updateAvailable.needsDownload, isTrue);
      expect(PluginStoreInstallState.upToDate.needsDownload, isFalse);
    });

    test('minAppVersion 校验: 未声明放行, 不满足则拦截', () {
      expect(PluginStoreSemantics.meetsMinAppVersion('0.1.0', null), isTrue);
      expect(PluginStoreSemantics.meetsMinAppVersion('0.1.0', ''), isTrue);
      expect(PluginStoreSemantics.meetsMinAppVersion('0.1.0', '0.1.0'), isTrue);
      expect(PluginStoreSemantics.meetsMinAppVersion('0.2.0', '0.1.0'), isTrue);
      expect(
          PluginStoreSemantics.meetsMinAppVersion('0.1.0', '0.2.0'), isFalse);
      expect(PluginStoreSemantics.meetsMinAppVersion('dev-build', '0.1.0'),
          isFalse);
    });
  });

  group('JsDelivrPluginStoreSource 目录拉取', () {
    test('一次清单请求即可归并 plugin-source 元数据与 dist 产物', () async {
      final httpClient = buildFakeCdn();
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: httpClient,
      );

      final catalog = await source.fetchCatalog();

      expect(catalog.entries.map((e) => e.id).toList(),
          ['base64_tool', 'unpacked_tool']);

      final entry = catalog.entries.first;
      expect(entry.name, 'Base64 编解码');
      expect(entry.version, '1.1.0');
      expect(entry.description, 'Base64 文本编码与解码转换工具');
      expect(entry.author, 'PluginToolbox Team');
      expect(entry.category, 'encoding');
      expect(entry.permissions, ['clipboard']);
      expect(entry.minAppVersion, '0.1.0');
      expect(entry.packageName, 'base64_tool.ptx');
      expect(entry.packageSizeBytes, 2246);
      expect(entry.packageSizeLabel, '2.2 KB');
      expect(entry.packageHash, jsDelivrHashOf(fakePtxBytes),
          reason: '目录条目必须携带清单接口给出的内容哈希，供下载后校验完整性');
      expect(
          entry.packageUrl,
          contains(
              'cdn.jsdelivr.net/gh/owner/repo@$testRef/dist/base64_tool.ptx'));
      expect(entry.sourcePath, 'plugin-source/base64_tool');
      expect(catalog.revision, testRef);

      // 尚未打包的插件仍在目录中, 但没有下载地址
      final unpacked = catalog.entries[1];
      expect(unpacked.id, 'unpacked_tool');
      expect(unpacked.packageUrl, isNull);
      expect(unpacked.packageHash, isNull);
      expect(unpacked.packageSizeLabel, '未知');

      // 清单 id 与目录名不一致的脏数据被跳过, 且不阻断整次拉取
      expect(catalog.skipped.single, contains('broken_tool'));

      // 请求数 = 1 次清单 + 3 次 plugin.json (嵌套 ui 目录与根文件不参与)
      expect(httpClient.requestCount, 4);
    });

    test('第二次刷新命中缓存, 只剩清单接口 1 次请求', () async {
      final httpClient = buildFakeCdn();
      final prefs = await SharedPreferences.getInstance();
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: httpClient,
        preferences: prefs,
      );

      await source.fetchCatalog();
      final afterFirst = httpClient.requestCount;
      expect(afterFirst, 4);

      // 用同一份持久化缓存新建实例, 模拟应用重启后的刷新
      final secondHttpClient = buildFakeCdn();
      final restarted = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: secondHttpClient,
        preferences: prefs,
      );
      final catalog = await restarted.fetchCatalog();

      expect(secondHttpClient.requestCount, 1, reason: '插件清单未变化时不应重复下载');
      expect(catalog.entries.map((e) => e.id).toList(),
          ['base64_tool', 'unpacked_tool']);
      expect(catalog.entries.first.version, '1.1.0');
    });

    test('清单缓存损坏时静默降级为全量拉取', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'plugin_store_cache_owner_repo_$testRef', 'not-json{{{');

      final httpClient = buildFakeCdn();
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: httpClient,
        preferences: prefs,
      );

      final catalog = await source.fetchCatalog();
      expect(catalog.entries.length, 2);
      expect(httpClient.requestCount, 4);
    });

    test('限流时给出可展示的中文提示', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(rateLimited: true),
      );

      await expectLater(
        source.fetchCatalog(),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('过于频繁'))),
      );
    });

    test('断网时给出网络错误提示而非空目录', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(offline: true),
      );

      await expectLater(
        source.fetchCatalog(),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('无法连接插件商店'))),
      );
    });

    test('清单结构异常时抛出明确错误', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient:
            FakeHttpClient((_) async => jsonResponse({'files': 'oops'})),
      );

      await expectLater(
          source.fetchCatalog(), throwsA(isA<PluginStoreException>()));
    });
  });

  group('JsDelivrPluginStoreSource 安装包下载', () {
    test('目录条目经完整性校验后下载并返回原始字节', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(),
      );

      final catalog = await source.fetchCatalog();
      final bytes = await source.downloadPackage(catalog.entries.first);

      expect(bytes, fakePtxBytes);
      expect(
          PluginManifest.fromJsonString(
            utf8.decode(
              ZipDecoder().decodeBytes(bytes).findFile('plugin.json')!.content
                  as List<int>,
            ),
          ).version,
          '1.1.0');
    });

    test('哈希为 base64 或十六进制形式时均判定一致', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(),
      );
      const url =
          'https://cdn.jsdelivr.net/gh/owner/repo@$testRef/dist/base64_tool.ptx';

      final viaBase64 = await source.downloadPackage(entryWith(
        packageUrl: url,
        packageHash: base64.encode(sha256.convert(fakePtxBytes).bytes),
      ));
      expect(viaBase64, fakePtxBytes);

      final viaHex = await source.downloadPackage(entryWith(
        packageUrl: url,
        packageHash: sha256.convert(fakePtxBytes).toString(),
      ));
      expect(viaHex, fakePtxBytes);
    });

    test('下载字节与清单哈希不匹配时判定被篡改并拒绝', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(),
      );

      await expectLater(
        source.downloadPackage(entryWith(
          packageUrl:
              'https://cdn.jsdelivr.net/gh/owner/repo@$testRef/dist/base64_tool.ptx',
          packageHash: jsDelivrHashOf(utf8.encode('tampered content')),
        )),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('哈希校验失败'))),
      );
    });

    test('条目缺少内容哈希时 fail-closed 拒绝下载', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(),
      );

      await expectLater(
        source.downloadPackage(entryWith(
          packageUrl:
              'https://cdn.jsdelivr.net/gh/owner/repo@$testRef/dist/base64_tool.ptx',
        )),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('缺少内容哈希'))),
      );
    });

    test('未打包的条目没有下载地址时给出明确错误', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        httpClient: buildFakeCdn(),
      );

      await expectLater(
        source.downloadPackage(entryWith(id: 'unpacked_tool')),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('远端缺少安装包'))),
      );
    });

    test('超过体积上限的安装包被拒绝', () async {
      final source = JsDelivrPluginStoreSource(
        owner: 'owner',
        repository: 'repo',
        ref: testRef,
        maxPackageBytes: 4,
        httpClient: buildFakeCdn(),
      );

      await expectLater(
        source.downloadPackage(entryWith(
          packageUrl:
              'https://cdn.jsdelivr.net/gh/owner/repo@$testRef/dist/base64_tool.ptx',
        )),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('过大'))),
      );
    });
  });

  group('安装包契约核对 inspectPluginPackage', () {
    test('清单、入口脚本与 UI 齐备时判定一致', () {
      final contract = inspectPluginPackage(buildPtx());
      expect(contract.manifest.id, 'base64_tool');
      expect(contract.manifest.version, '1.1.0');
      expect(contract.missingEntryScript, isFalse);
      expect(contract.missingUiDefinition, isFalse);
      expect(contract.isConsistent, isTrue);
      expect(contract.entryNames, contains('plugin.json'));
    });

    test('入口脚本或 UI 缺失时精确指出缺哪一项', () {
      final missingEntry = inspectPluginPackage(buildPtx(includeEntry: false));
      expect(missingEntry.missingEntryScript, isTrue);
      expect(missingEntry.missingUiDefinition, isFalse);
      expect(missingEntry.isConsistent, isFalse);

      final missingUi = inspectPluginPackage(buildPtx(includeUi: false));
      expect(missingUi.missingUiDefinition, isTrue);
    });

    test('非 ZIP 内容与缺少清单均抛出可展示错误', () {
      expect(
        () => inspectPluginPackage(Uint8List.fromList(List<int>.filled(64, 7))),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('ZIP'))),
      );

      final archive = Archive();
      final junk = utf8.encode('return nil');
      archive.addFile(ArchiveFile('main.lua', junk.length, junk));
      expect(
        () => inspectPluginPackage(
            Uint8List.fromList(ZipEncoder().encode(archive)!)),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('plugin.json'))),
      );
    });
  });

  group('PluginRepositoryConfig 自定义仓库坐标模型', () {
    test('正确解析各种格式的 GitHub 仓库链接与简写', () {
      final fromHttps = PluginRepositoryConfig.tryParse(
          'https://github.com/my-org/custom-plugins');
      expect(fromHttps, isNotNull);
      expect(fromHttps!.owner, 'my-org');
      expect(fromHttps.repository, 'custom-plugins');
      expect(fromHttps.githubUrl, 'https://github.com/my-org/custom-plugins');
      expect(fromHttps.summary, 'my-org/custom-plugins');

      // 带 .git 与末尾斜杠
      final fromGit = PluginRepositoryConfig.tryParse(
          'https://github.com/my-org/custom-plugins.git/');
      expect(fromGit, isNotNull);
      expect(fromGit!.owner, 'my-org');
      expect(fromGit.repository, 'custom-plugins');

      // 简写形式 owner/repo
      final fromShort =
          PluginRepositoryConfig.tryParse('developer_team/tools.v2');
      expect(fromShort, isNotNull);
      expect(fromShort!.owner, 'developer_team');
      expect(fromShort.repository, 'tools.v2');

      // 无协议头 github.com/owner/repo
      final fromDomain = PluginRepositoryConfig.tryParse('github.com/foo/bar');
      expect(fromDomain, isNotNull);
      expect(fromDomain!.owner, 'foo');
      expect(fromDomain.repository, 'bar');
    });

    test('默认官方仓库状态与等价性判定', () {
      const config = PluginRepositoryConfig.defaultConfig;
      expect(config.isDefault, isTrue);
      expect(config.owner, 'Aclguh');
      expect(config.repository, 'PTX-plugins');
      expect(config.githubUrl, 'https://github.com/Aclguh/PTX-plugins');

      final parsedDefault = PluginRepositoryConfig.tryParse(
          'https://github.com/aclguh/ptx-plugins');
      expect(parsedDefault, isNotNull);
      expect(parsedDefault!.isDefault, isTrue);
      expect(parsedDefault == config, isTrue);

      final custom = PluginRepositoryConfig.tryParse('other/repo');
      expect(custom!.isDefault, isFalse);
      expect(custom == config, isFalse);
    });

    test('拒绝非法格式与注入字符', () {
      expect(PluginRepositoryConfig.tryParse(null), isNull);
      expect(PluginRepositoryConfig.tryParse('   '), isNull);
      expect(PluginRepositoryConfig.tryParse('https://gitlab.com/foo/bar'),
          isNull);
      expect(PluginRepositoryConfig.tryParse('single-word'), isNull);
      expect(PluginRepositoryConfig.tryParse('foo/bar/baz'), isNull);
      expect(PluginRepositoryConfig.tryParse('-invalid-user/repo'), isNull);
      expect(PluginRepositoryConfig.tryParse('user/..'), isNull);
      expect(PluginRepositoryConfig.tryParse('user/repo with spaces'), isNull);
    });
  });
}
