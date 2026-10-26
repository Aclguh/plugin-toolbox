import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'helpers/lua_test_helpers.dart';

Future<void> _waitFor(
  bool Function() condition, {
  int maxTries = 40,
  int stepMs = 25,
}) =>
    waitForCondition(condition, maxTries: maxTries, stepMs: stepMs);

void main() {
  group('Lua Data & Services APIs', () {
    late MockLuaHostDelegate delegate;
    late PluginContext context;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {
          PluginPermission.clipboard,
          PluginPermission.storage,
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('json 全局表以绑定形式注入 (仅验证绑定, 不验证业务数据)', () {
      engine.loadAndExecute('''
        state.set("json_type", type(json))
        state.set("json_encode_fn", type(json.encode))
        state.set("json_decode_fn", type(json.decode))
      ''');

      expect(delegate.getState('json_type'), 'table');
      expect(delegate.getState('json_encode_fn'), 'function');
      expect(delegate.getState('json_decode_fn'), 'function');
    });

    test('json.encode 将 Lua 表结构序列化为 JSON 字符串', () {
      engine.loadAndExecute('''
        function enc()
          return json.encode({
            hello = "world",
            n = 3,
            arr = {1, 2, 3},
            flag = true,
            nested = { inner = {1, 2} },
          })
        end
      ''');

      final out = engine.callFunction('enc') as String;
      final parsed = jsonDecode(out) as Map<String, dynamic>;
      expect(parsed['hello'], 'world');
      expect(parsed['n'], 3);
      expect(parsed['arr'], [1, 2, 3]);
      expect(parsed['flag'], true);
      expect(parsed['nested'], {
        'inner': [1, 2]
      });
    });

    test('json.encode 标量与空表', () {
      engine.loadAndExecute('''
        function enc_scalar()
          return json.encode(42)
        end
        function enc_str()
          return json.encode("hi")
        end
        function enc_empty()
          return json.encode({})
        end
      ''');

      expect(engine.callFunction('enc_scalar'), '42');
      expect(engine.callFunction('enc_str'), '"hi"');
      // 空表无 1..N 数组特征, 统一按对象序列化
      expect(engine.callFunction('enc_empty'), '{}');
    });

    test('json.decode 将 JSON 文本还原为 Lua 表结构', () {
      engine.loadAndExecute('''
        function dec(s)
          return json.decode(s)
        end
      ''');

      // null 值依 Lua 表语义表现为键缺失 (赋 nil 即删除键)
      final obj = engine.callFunction(
          'dec', ['{"a":[1,2,{"b":null}],"s":"x","f":1.5,"ok":true}']);
      expect(obj, {
        'a': [1, 2, {}],
        's': 'x',
        'f': 1.5,
        'ok': true,
      });
      expect(engine.callFunction('dec', ['[10,20]']), [10, 20]);
      expect(engine.callFunction('dec', ['null']), isNull);
    });

    test('json.decode 后再 encode 与压缩输入保持结构等价', () {
      engine.loadAndExecute('''
        function roundtrip(s)
          return json.encode(json.decode(s))
        end
      ''');

      expect(
        engine.callFunction('roundtrip', ['{ "a" : [1, 2], "b" : "x" }']),
        '{"a":[1,2],"b":"x"}',
      );
    });

    test('json.encode 循环引用表降级为 Lua 执行错误 (不逃逸宿主)', () {
      engine.loadAndExecute('''
        function makeCyclic()
          local t = {}
          t.self = t
          return json.encode(t)
        end
      ''');

      expect(
        () => engine.callFunction('makeCyclic'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('循环引用'),
        )),
      );
    });

    test('json.encode 不可序列化类型与 json.decode 非法输入均被 pcall 隔离', () {
      engine.loadAndExecute('''
        function tryEncodeFn()
          local ok, err = pcall(json.encode, {f = print})
          state.set("enc_ok", ok)
        end
        function tryDecodeBad()
          local ok, err = pcall(json.decode, "{bad json")
          state.set("dec_ok", ok)
        end
      ''');

      engine.callFunction('tryEncodeFn');
      expect(delegate.getState('enc_ok'), false);
      engine.callFunction('tryDecodeBad');
      expect(delegate.getState('dec_ok'), false);
    });

    test('超深嵌套 JSON 在解析前被深度预检拦截', () {
      final deep = ('[' * 100) + (']' * 100);
      engine.loadAndExecute('''
        function tryDeep(s)
          local ok = pcall(json.decode, s)
          state.set("deep_ok", ok)
        end
      ''');

      engine.callFunction('tryDeep', [deep]);
      expect(delegate.getState('deep_ok'), false);
    });

    test('Lua 异步回调异常被安全捕获并通知 onCallbackError', () async {
      String? callbackErr;
      final testEngine = LuaEngine(
        context: context,
        delegate: delegate,
        onCallbackError: (err) {
          callbackErr = err;
        },
      );
      addTearDown(testEngine.close);

      testEngine.loadAndExecute('''
        timer.setTimeout(10, function()
          error("Async callback boom")
        end)
      ''');

      await _waitFor(() => callbackErr != null);
      expect(callbackErr, contains('Async callback boom'));
    });

    test('CryptoApi HMAC 与 SHA512 计算', () {
      engine.loadAndExecute('''
        state.set("h_md5", crypto.hmacMd5("key", "data"))
        state.set("h_sha1", crypto.hmacSha1("key", "data"))
        state.set("h_sha256", crypto.hmacSha256("key", "data"))
        state.set("sha512", crypto.sha512("data"))
      ''');

      expect(delegate.getState('h_md5'), isA<String>());
      expect(delegate.getState('h_sha1'), isA<String>());
      expect(delegate.getState('h_sha256'), isA<String>());
      expect((delegate.getState('sha512') as String).length, 128);
    });

    test('CryptoApi AES CBC/ECB 加解密、SM3、PBKDF2 与 randomBytes 计算', () {
      engine.loadAndExecute('''
        local secret = "Hello PluginToolbox 2026!"
        local key = "1234567890123456"
        local iv = "abcdefghijklmnop"

        -- CBC
        local cbc_enc = crypto.aesEncrypt(secret, key, iv, "cbc")
        local cbc_dec = crypto.aesDecrypt(cbc_enc, key, iv, "cbc")
        state.set("cbc_enc", cbc_enc)
        state.set("cbc_dec", cbc_dec)

        -- ECB
        local ecb_enc = crypto.aesEncrypt(secret, key, nil, "ecb")
        local ecb_dec = crypto.aesDecrypt(ecb_enc, key, nil, "ecb")
        state.set("ecb_dec", ecb_dec)

        -- SM3
        local sm3_val = crypto.sm3("abc")
        state.set("sm3_val", sm3_val)

        -- PBKDF2
        local pbkdf2_val = crypto.pbkdf2("password", "salt", 1000, 32)
        state.set("pbkdf2_val", pbkdf2_val)

        -- randomBytes
        local rand_val = crypto.randomBytes(16)
        state.set("rand_val", rand_val)
      ''');

      expect(delegate.getState('cbc_enc'), isA<String>());
      expect(delegate.getState('cbc_dec'), 'Hello PluginToolbox 2026!');
      expect(delegate.getState('ecb_dec'), 'Hello PluginToolbox 2026!');
      // SM3("abc") 标准测试向量: 66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0
      expect(delegate.getState('sm3_val'),
          '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0');
      expect((delegate.getState('pbkdf2_val') as String).length, 64);
      expect((delegate.getState('rand_val') as String).length, 32);
    });

    test('RegexApi 正则匹配、查找与替换', () {
      engine.loadAndExecute('''
        state.set("is_match", regex.test("^\\\\d+\$", "12345"))
        state.set("not_match", regex.test("^\\\\d+\$", "123a"))
        state.set("first", regex.firstMatch("\\\\d+", "abc123def456"))
        
        local all = regex.findAll("\\\\d+", "abc123def456")
        state.set("all_count", #all)
        state.set("all_1", all[1])
        state.set("all_2", all[2])

        state.set("replaced", regex.replace("\\\\d+", "a1b2c", "#"))
        state.set("replaced_all", regex.replaceAll("\\\\d+", "a1b2c", "#"))
      ''');

      expect(delegate.getState('is_match'), true);
      expect(delegate.getState('not_match'), false);
      expect(delegate.getState('first'), '123');
      expect(delegate.getState('all_count'), 2);
      expect(delegate.getState('all_1'), '123');
      expect(delegate.getState('all_2'), '456');
      expect(delegate.getState('replaced'), 'a#b2c');
      expect(delegate.getState('replaced_all'), 'a#b#c');
    });

    test('ColorApi Hex, RGB 与 HSL 颜色空间互相转换', () {
      engine.loadAndExecute('''
        local rgb = color.hexToRgb("#FF8000")
        state.set("rgb_r", rgb.r)
        state.set("rgb_g", rgb.g)
        state.set("rgb_b", rgb.b)

        state.set("hex_str", color.rgbToHex(255, 128, 0))

        local hsl = color.rgbToHsl(255, 0, 0)
        state.set("hsl_h", hsl.h)
        state.set("hsl_s", hsl.s)
        state.set("hsl_l", hsl.l)

        local fromHsl = color.hslToRgb(0, 1.0, 0.5)
        state.set("from_h_r", fromHsl.r)
        state.set("from_h_g", fromHsl.g)
        state.set("from_h_b", fromHsl.b)
      ''');

      expect(delegate.getState('rgb_r'), 255);
      expect(delegate.getState('rgb_g'), 128);
      expect(delegate.getState('rgb_b'), 0);
      expect(delegate.getState('hex_str'), '#FF8000');
      expect(delegate.getState('hsl_h'), 0.0);
      expect(delegate.getState('hsl_s'), 1.0);
      expect(delegate.getState('hsl_l'), 0.5);
      expect(delegate.getState('from_h_r'), 255);
      expect(delegate.getState('from_h_g'), 0);
      expect(delegate.getState('from_h_b'), 0);
    });

    test('UtilApi formatTime 与 parseTime', () {
      engine.loadAndExecute('''
        local ms = 1700000000000
        local formatted = util.formatTime(ms, "yyyy-MM-dd HH:mm:ss")
        state.set("formatted", formatted)
        local parsed = util.parseTime(formatted, "yyyy-MM-dd HH:mm:ss")
        state.set("parsed_ms", parsed)
      ''');

      expect(delegate.getState('formatted'), isA<String>());
      expect(delegate.getState('parsed_ms'), 1700000000000);
    });

    test('DocumentApi: csvParse 与 csvStringify 往返转换', () {
      engine.loadAndExecute('''
        local csv = 'name,score,desc\\nAlice,100,"good, job"\\nBob,90,"said ""hi"""'
        local rows = document.csvParse(csv)
        state.set("row_count", #rows)
        state.set("r1_c1", rows[1][1])
        state.set("r2_c3", rows[2][3])
        state.set("r3_c3", rows[3][3])

        local stringified = document.csvStringify(rows)
        state.set("stringified", stringified)
        local re_rows = document.csvParse(stringified)
        state.set("re_row_count", #re_rows)
        state.set("re_r2_c3", re_rows[2][3])
      ''');

      expect(delegate.getState('row_count'), 3);
      expect(delegate.getState('r1_c1'), 'name');
      expect(delegate.getState('r2_c3'), 'good, job');
      expect(delegate.getState('r3_c3'), 'said "hi"');
      expect(delegate.getState('re_row_count'), 3);
      expect(delegate.getState('re_r2_c3'), 'good, job');
    });

    test('DocumentApi: markdownToHtml 标题、强调与代码块', () {
      engine.loadAndExecute('''
        local md = "# Hello\\n**Bold text** and `inline code`\\n- Item 1\\n- Item 2"
        local html = document.markdownToHtml(md)
        state.set("html", html)
      ''');

      final html = delegate.getState('html') as String;
      expect(html, contains('<h1>Hello</h1>'));
      expect(html, contains('<strong>Bold text</strong>'));
      expect(html, contains('<code>inline code</code>'));
      expect(html, contains('<li>Item 1</li>'));
      expect(html, contains('<li>Item 2</li>'));
    });

    test('DocumentApi: YAML 与 XML 往返解析与序列化', () {
      engine.loadAndExecute('''
        -- YAML
        local yamlStr = "name: PluginToolbox\\nversion: 2\\nenabled: true\\ntags:\\n  - utility\\n  - mobile\\n"
        local yamlData = document.yamlParse(yamlStr)
        state.set("y_name", yamlData.name)
        state.set("y_ver", yamlData.version)
        state.set("y_tag1", yamlData.tags[1])

        local reYaml, y_err = document.yamlStringify(yamlData)
        state.set("re_yaml", reYaml)
        state.set("y_err", y_err)

        -- XML
        local xmlStr = '<plugin id="tool_1" version="1.0"><title>Tool Title</title><author>Dev</author></plugin>'
        local xmlData = document.xmlParse(xmlStr)
        state.set("x_tag", xmlData.tag)
        state.set("x_id", xmlData.attrs.id)
        state.set("x_child_count", #xmlData.children)
        state.set("x_c1_tag", xmlData.children[1].tag)
        state.set("x_c1_text", xmlData.children[1].text)

        local reXml = document.xmlStringify(xmlData)
        state.set("re_xml", reXml)
      ''');

      expect(delegate.getState('y_name'), 'PluginToolbox');
      expect(delegate.getState('y_ver'), 2);
      expect(delegate.getState('y_tag1'), 'utility');
      expect((delegate.getState('re_yaml') as String),
          contains('name: PluginToolbox'));

      expect(delegate.getState('x_tag'), 'plugin');
      expect(delegate.getState('x_id'), 'tool_1');
      expect(delegate.getState('x_child_count'), 2);
      expect(delegate.getState('x_c1_tag'), 'title');
      expect(delegate.getState('x_c1_text'), 'Tool Title');
      expect((delegate.getState('re_xml') as String), contains('id="tool_1"'));
      expect(
          (delegate.getState('re_xml') as String), contains('version="1.0"'));
      expect((delegate.getState('re_xml') as String),
          contains('<title>Tool Title</title>'));
    });

    test('I18nApi: 语言查询、动态切换、沙箱字典加载与插值回退', () {
      final tempDir = Directory.systemTemp.createTempSync('i18n_test_');
      final localesDir = Directory('${tempDir.path}/locales')
        ..createSync(recursive: true);
      File('${localesDir.path}/zh.json')
          .writeAsStringSync('{"welcome": "你好，{{name}}！", "app_title": "工具箱"}');
      File('${localesDir.path}/en.json').writeAsStringSync(
          '{"welcome": "Hello, {{name}}!", "app_title": "Toolbox"}');

      final i18nCtx = PluginContext(
        pluginId: 'i18n_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: const {},
        rootDir: tempDir,
      );
      final i18nEngine = LuaEngine(context: i18nCtx, delegate: delegate);

      i18nEngine.loadAndExecute('''
        -- 初始 locale
        state.set("init_locale", i18n.locale())

        -- 设置为中文
        i18n.setLocale("zh")
        state.set("zh_t", i18n.t("welcome", { name = "小明" }))
        state.set("zh_title", i18n.t("app_title"))

        -- 切换为英文
        i18n.setLocale("en")
        state.set("en_t", i18n.t("welcome", { name = "Alice" }))
        state.set("en_title", i18n.t("app_title"))

        -- 回退测试: 不存在的 key 返回 key 本身
        state.set("fallback_key", i18n.t("non_exist_key"))

        -- 查询所有语言
        local all = i18n.allLocales()
        state.set("locale_count", #all)
      ''');

      expect(delegate.getState('init_locale'), isA<String>());
      expect(delegate.getState('zh_t'), '你好，小明！');
      expect(delegate.getState('zh_title'), '工具箱');
      expect(delegate.getState('en_t'), 'Hello, Alice!');
      expect(delegate.getState('en_title'), 'Toolbox');
      expect(delegate.getState('fallback_key'), 'non_exist_key');
      expect(delegate.getState('locale_count'), 2);

      i18nEngine.close();
      tempDir.deleteSync(recursive: true);
    });

    test('QrcodeApi: 生成二维码矩阵与尺寸', () {
      engine.loadAndExecute('''
        local res = qrcode.matrix("https://github.com")
        state.set("qr_cols", res.cols)
        state.set("qr_rows", res.rows)
        state.set("qr_len", string.len(res.data))
      ''');

      final cols = delegate.getState('qr_cols') as int;
      final rows = delegate.getState('qr_rows') as int;
      final len = delegate.getState('qr_len') as int;

      expect(cols, greaterThan(0));
      expect(rows, cols);
      expect(len, cols * rows);
    });

    test('TaskApi: task.run 后台 Worker 并发计算与回调通知', () async {
      engine.loadAndExecute('''
        -- 1. 携带 main(args) 函数的 Worker 计算
        task.run([[
          function main(args)
            return args.a + args.b
          end
        ]], { a = 12, b = 30 }, function(res)
          state.set("task_sum_ok", res.ok)
          state.set("task_sum_val", res.result)
        end)

        -- 2. 直接 return 表达式的轻量 Worker 计算
        task.run("return string.upper('hello worker')", function(res)
          state.set("task_upper_ok", res.ok)
          state.set("task_upper_val", res.result)
        end)

        -- 3. 语法错误时返回 ok=false 并捕获错误原因
        task.run("syntax error !!!", function(res)
          state.set("task_err_ok", res.ok)
          state.set("task_err_has_msg", res.error ~= nil)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('task_sum_ok') != null &&
          delegate.getState('task_upper_ok') != null &&
          delegate.getState('task_err_ok') != null);
      expect(delegate.getState('task_sum_ok'), isTrue);
      expect(delegate.getState('task_sum_val'), 42);
      expect(delegate.getState('task_upper_ok'), isTrue);
      expect(delegate.getState('task_upper_val'), 'HELLO WORKER');
      expect(delegate.getState('task_err_ok'), isFalse);
      expect(delegate.getState('task_err_has_msg'), isTrue);
    });

    test('TaskApi: task.parallel 并发执行多任务聚合', () async {
      engine.loadAndExecute('''
        local tasks = {
          { script = "return 10 * 2" },
          { script = "function main(x) return x .. ' world' end", args = "hello" },
          { script = "return hash.md5('toolbox')" }
        }

        task.parallel(tasks, function(res)
          state.set("parallel_ok", res.ok)
          state.set("parallel_res1", res.results[1].result)
          state.set("parallel_res2", res.results[2].result)
          state.set("parallel_res3", res.results[3].result)
        end)
      ''');

      await _waitFor(() => delegate.getState('parallel_ok') != null);
      expect(delegate.getState('parallel_ok'), isTrue);
      expect(delegate.getState('parallel_res1'), 20);
      expect(delegate.getState('parallel_res2'), 'hello world');
      expect(delegate.getState('parallel_res3'), isNotEmpty);
    });

    test('DatabaseApi: 沙箱内纯 Dart 结构化 SQL 引擎执行与查询', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_db_test_');
      final dbCtx = PluginContext(
        pluginId: 'db_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.database},
      );
      final dbEngine = LuaEngine(context: dbCtx, delegate: delegate);

      dbEngine.loadAndExecute('''
        -- 1. 创建表
        db.execute("CREATE TABLE users (id, name, score)", function(res)
          state.set("db_create_ok", res.ok)
        end)

        -- 2. 插入多条记录
        db.execute("INSERT INTO users (id, name, score) VALUES (?, ?, ?)", { 1, "Alice", 95 }, function(res)
          state.set("db_ins1_ok", res.ok)
        end)
        db.execute("INSERT INTO users (id, name, score) VALUES (?, ?, ?)", { 2, "Bob", 80 }, function(res)
          state.set("db_ins2_ok", res.ok)
        end)

        -- 3. 条件与排序查询
        db.query("SELECT * FROM users WHERE score = ? ORDER BY score DESC", { 95 }, function(res)
          state.set("db_query_ok", res.ok)
          state.set("db_query_err", res.error)
          if res.rows and res.rows[1] then
            state.set("db_query_name", res.rows[1].name)
          end
        end)

        -- 4. 更新记录
        db.execute("UPDATE users SET score = ? WHERE name = ?", { 100, "Alice" }, function(res)
          state.set("db_update_ok", res.ok)
        end)

        -- 5. 批量处理
        db.batch({
          "INSERT INTO users (id, name, score) VALUES (3, 'Charlie', 88)",
          "DELETE FROM users WHERE name = 'Bob'"
        }, function(res)
          state.set("db_batch_ok", res.ok)
        end)
      ''');

      await _waitFor(() => delegate.getState('db_batch_ok') != null);
      expect(delegate.getState('db_create_ok'), isTrue);
      expect(delegate.getState('db_ins1_ok'), isTrue);
      expect(delegate.getState('db_ins2_ok'), isTrue);
      expect(delegate.getState('db_query_ok'), isTrue);
      expect(delegate.getState('db_query_name'), 'Alice');
      expect(delegate.getState('db_update_ok'), isTrue);
      expect(delegate.getState('db_batch_ok'), isTrue);

      // 6. 测试增强 SQL: 多行注释清洗、字面量插入与 COUNT 统计、多条件过滤
      dbEngine.loadAndExecute('''
        local sql = [[
          /* 多行 SQL 注释 */
          -- 单行 SQL 注释
          SELECT COUNT(*) AS total FROM users WHERE score >= 88 AND name LIKE 'C%'
        ]]
        db.query(sql, {}, function(res)
          if res.ok and res.rows and res.rows[1] then
            state.set("db_count_val", res.rows[1].total)
          end
        end)
      ''');

      await _waitFor(() => delegate.getState('db_count_val') != null);
      expect(delegate.getState('db_count_val'), 1);

      // 7. 测试显式 flush 刷盘
      dbEngine.loadAndExecute('''
        db.flush(function(res)
          state.set("db_flush_ok", res.ok)
        end)
      ''');
      await _waitFor(() => delegate.getState('db_flush_ok') != null);
      expect(delegate.getState('db_flush_ok'), isTrue);

      final dbFile = File('${tempDir.path}/plugin_data.db');
      expect(dbFile.existsSync(), isTrue);

      dbEngine.close();
      await tempDir.delete(recursive: true);
    });

    test('DatabaseApi: 批量处理单次合并落盘与脏写节流写入机制', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_db_batch_');
      final dbCtx = PluginContext(
        pluginId: 'db_batch_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.database},
      );
      final dbEngine = LuaEngine(context: dbCtx, delegate: delegate);

      // 批量创建和插入 20 条记录，并在无阻塞情况下迅速完成
      dbEngine.loadAndExecute('''
        db.execute("CREATE TABLE items (id, name, val)", function(res)
          state.set("batch_create_ok", res.ok)
        end)

        local stmts = {}
        for i = 1, 20 do
          table.insert(stmts, "INSERT INTO items (id, name, val) VALUES (" .. i .. ", 'item_" .. i .. "', " .. (i * 10) .. ")")
        end

        db.batch(stmts, function(res)
          state.set("batch_res_ok", res.ok)
          state.set("batch_res_affected", res.totalAffected)
        end)

        db.query("SELECT COUNT(*) AS c FROM items", {}, function(res)
          if res.ok and res.rows and res.rows[1] then
            state.set("batch_query_count", res.rows[1].c)
          end
        end)
      ''');

      await _waitFor(() => delegate.getState('batch_query_count') != null);
      expect(delegate.getState('batch_create_ok'), isTrue);
      expect(delegate.getState('batch_res_ok'), isTrue);
      expect(delegate.getState('batch_res_affected'), 20);
      expect(delegate.getState('batch_query_count'), 20);

      dbEngine.close();
      final dbFile = File('${tempDir.path}/plugin_data.db');
      expect(dbFile.existsSync(), isTrue);
      await tempDir.delete(recursive: true);
    });

    test('DatabaseApi: 特殊字符字面量与 .bak 备份恢复容错', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_db_special_');
      final dbCtx = PluginContext(
        pluginId: 'db_special_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.database},
      );
      final dbEngine = LuaEngine(context: dbCtx, delegate: delegate);

      dbEngine.loadAndExecute('''
        db.execute("CREATE TABLE posts (id, title, tag)", function(res) end)
        db.execute("INSERT INTO posts (id, title, tag) VALUES (1, 'A AND B', 'uuid--123')", function(res)
          state.set("ins_special_ok", res.ok)
        end)
        db.query("SELECT * FROM posts WHERE title = 'A AND B' AND tag = 'uuid--123'", {}, function(res)
          state.set("query_special_ok", res.ok)
          if res.rows and res.rows[1] then
            state.set("query_special_title", res.rows[1].title)
          end
        end)
        db.flush(function(res)
          state.set("special_flush_ok", res.ok)
        end)
      ''');

      for (var i = 0; i < 40; i++) {
        if (delegate.getState('special_flush_ok') == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(delegate.getState('ins_special_ok'), isTrue);
      expect(delegate.getState('query_special_ok'), isTrue);
      expect(delegate.getState('query_special_title'), 'A AND B');
      expect(delegate.getState('special_flush_ok'), isTrue);
      dbEngine.close();

      // 验证 .bak 备份恢复：触发第二次落盘生成 bak，破坏主文件后仍可从 bak 恢复读取
      final dbFile = File('${tempDir.path}/plugin_data.db');
      final bakFile = File('${tempDir.path}/plugin_data.db.bak');
      expect(dbFile.existsSync(), isTrue);

      final dbEngine2 = LuaEngine(context: dbCtx, delegate: delegate);
      dbEngine2.loadAndExecute('''
        db.execute("INSERT INTO posts (id, title, tag) VALUES (2, 'Second', 'tag')", function(res) end)
        db.flush(function(res)
          state.set("flush2_ok", res.ok)
        end)
      ''');
      for (var i = 0; i < 40; i++) {
        if (delegate.getState('flush2_ok') == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(delegate.getState('flush2_ok'), isTrue);
      dbEngine2.close();
      expect(bakFile.existsSync(), isTrue);

      // 损坏主文件
      dbFile.writeAsStringSync('{corrupted_json:::');

      final dbEngine3 = LuaEngine(context: dbCtx, delegate: delegate);
      dbEngine3.loadAndExecute('''
        db.query("SELECT COUNT(*) AS c FROM posts", {}, function(res)
          if res.ok and res.rows and res.rows[1] then
            state.set("recovered_count", res.rows[1].c)
          end
        end)
      ''');
      for (var i = 0; i < 40; i++) {
        if (delegate.getState('recovered_count') != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(delegate.getState('recovered_count'), isNotNull);
      dbEngine3.close();

      await tempDir.delete(recursive: true);
    });

    test('DatabaseApi: SELECT 投影、ORDER BY (含 null)、LIMIT 与 OFFSET 分页查询',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_db_advanced_');
      final dbCtx = PluginContext(
        pluginId: 'db_advanced_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.database},
      );
      final dbEngine = LuaEngine(context: dbCtx, delegate: delegate);

      dbEngine.loadAndExecute('''
        db.execute("CREATE TABLE items (id INT, name TEXT, score INT)", function(res) end)
        db.execute("INSERT INTO items (id, name, score) VALUES (1, 'Alice', 90)", function(res) end)
        db.execute("INSERT INTO items (id, name, score) VALUES (2, 'Bob', 80)", function(res) end)
        db.execute("INSERT INTO items (id, name, score) VALUES (3, 'Charlie', 95)", function(res) end)
        db.execute("INSERT INTO items (id, name, score) VALUES (4, 'Dave', nil)", function(res) end)

        -- 投影列 + ORDER BY score DESC + LIMIT 2 OFFSET 1
        db.query("SELECT name, score FROM items ORDER BY score DESC LIMIT 2 OFFSET 1", {}, function(res)
          state.set("q1_ok", res.ok)
          state.set("q1_err", res.error)
          if res.ok and res.rows then
            state.set("q1_count", #res.rows)
            if #res.rows >= 1 then state.set("row1_name", res.rows[1].name) end
            if #res.rows >= 2 then state.set("row2_name", res.rows[2].name) end
          end
        end)

        -- ORDER BY 升序 (null 在最前)
        db.query("SELECT name FROM items ORDER BY score ASC", {}, function(res)
          if res.ok and #res.rows >= 1 then
            state.set("asc_first_name", res.rows[1].name)
          end
        end)
      ''');

      for (var i = 0; i < 40; i++) {
        if (delegate.getState('row1_name') != null &&
            delegate.getState('asc_first_name') != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(delegate.getState('row1_name'), 'Alice');
      expect(delegate.getState('row2_name'), 'Bob');
      expect(delegate.getState('row2_name'), 'Bob');
      expect(delegate.getState('asc_first_name'), 'Dave');

      dbEngine.close();
      await tempDir.delete(recursive: true);
    });

    test('DatabaseApi: 支持注入自定义 PluginDatabaseFactory 驱动并透明调用', () async {
      final customDb = _MockCustomDatabase();
      final tempDir = Directory.systemTemp.createTempSync('ptx_custom_db_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final dbCtx = PluginContext(
        pluginId: 'custom_db_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.database},
        rootDir: tempDir,
      );
      final dbEngine = LuaEngine(
        context: dbCtx,
        delegate: delegate,
        databaseFactory: (file) => customDb,
      );
      addTearDown(dbEngine.close);

      dbEngine.loadAndExecute('''
        db.execute("INSERT INTO test (id) VALUES (1)", function(res)
          state.set("custom_ins_ok", res.ok)
        end)
      ''');

      for (var i = 0; i < 20; i++) {
        if (delegate.getState('custom_ins_ok') == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(delegate.getState('custom_ins_ok'), isTrue);
      expect(
          customDb.executedSqls, contains('INSERT INTO test (id) VALUES (1)'));
    });

    test('AiApi: 统一大模型网关 chat 与 streamChat 调用', () async {
      // 1. 无权限拦截
      expect(
        () =>
            engine.loadAndExecute('ai.chat({ messages = {} }, function() end)'),
        throwsException,
      );

      // 2. 有权限正常发起
      final aiCtx = PluginContext(
        pluginId: 'ai_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.ai},
      );
      final aiEngine = LuaEngine(context: aiCtx, delegate: delegate);

      aiEngine.loadAndExecute('''
        ai.isAvailable(function(avail)
          state.set("ai_avail", avail)
        end)

        ai.chat({
          messages = { { role = "user", content = "Hello AI" } },
          model = "gpt-4o",
          temperature = 0.5
        }, function(res)
          state.set("ai_chat_ok", res.ok)
          state.set("ai_chat_text", res.text)
        end)

        local chunks = ""
        ai.streamChat({
          messages = { { role = "user", content = "Stream test" } }
        }, function(chunk)
          chunks = chunks .. chunk
        end, function()
          state.set("ai_stream_text", chunks)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('ai_avail') != null &&
          delegate.getState('ai_chat_ok') != null &&
          delegate.getState('ai_stream_text') != null);
      expect(delegate.getState('ai_avail'), isTrue);
      expect(delegate.getState('ai_chat_ok'), isTrue);
      expect(delegate.getState('ai_chat_text'), 'AI generated response');
      expect(delegate.getState('ai_stream_text'), 'Chunk1 Chunk2');
    });

    test('IpcApi: 跨插件服务注册、RPC 调用与管道打开', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('plugin.call("other", "fn")'),
        throwsException,
      );

      // 2. 提供者插件 (provider) 注册接口
      final providerCtx = PluginContext(
        pluginId: 'provider_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.ipc},
      );
      final providerEngine =
          LuaEngine(context: providerCtx, delegate: delegate);

      providerEngine.loadAndExecute('''
        plugin.export("doubleNumber", function(num)
          return num * 2
        end)
      ''');

      // 3. 调用者插件 (caller) 进行 RPC 调用
      final callerCtx = PluginContext(
        pluginId: 'caller_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.ipc},
      );
      final callerEngine = LuaEngine(context: callerCtx, delegate: delegate);

      callerEngine.loadAndExecute('''
        plugin.call("provider_plugin", "doubleNumber", 21, function(res)
          state.set("ipc_call_ok", res.ok)
          state.set("ipc_call_val", res.result)
        end)

        plugin.open("diff_tool", { initialText = "compare me" }, function(res)
          state.set("ipc_open_ok", res.ok)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('ipc_call_ok') != null &&
          delegate.getState('ipc_open_ok') != null);
      expect(delegate.getState('ipc_call_ok'), isTrue);
      expect(delegate.getState('ipc_call_val'), 42);
      expect(delegate.getState('ipc_open_ok'), isTrue);
      expect(delegate.openedPluginId, 'diff_tool');
      expect(delegate.openedPluginData?['initialText'], 'compare me');

      // 关闭 provider 引擎后，其接口被自动注销
      providerEngine.close();
      expect(
        PluginIpcBroker.instance.hasService('provider_plugin', 'doubleNumber'),
        isFalse,
      );
    });

    test('CompositeLuaHostDelegate 领域子委托组合与状态穿透', () {
      final stateStorage = <String, dynamic>{};
      final stateDelegate = _SimpleStateDelegate(stateStorage);
      final composite = CompositeLuaHostDelegate(stateDelegate: stateDelegate);

      composite.onStateChanged('key1', 'val1');
      expect(composite.getState('key1'), 'val1');
      expect(composite.getAllStates()['key1'], 'val1');
      expect(composite.batteryLevel, 100);
      expect(composite.isTorchOn, isFalse);
    });

    test('DisposableTracker 集中资源生命周期逆序清理与异常隔离保护', () {
      final tracker = DisposableTracker();
      final logs = <String>[];

      tracker.addCallback(() => logs.add('step1'));
      tracker.addCallback(() {
        logs.add('step2_error');
        throw Exception('Boom');
      });
      tracker.addCallback(() => logs.add('step3'));

      // 逆序执行且异常隔离
      tracker.disposeAll();
      expect(logs, ['step3', 'step2_error', 'step1']);
    });

    test('StateApi 支持 Table 与复合结构双向读写', () async {
      final delegate = MockLuaHostDelegate();
      delegate.onStateChanged('initial_user', {'name': 'Bob', 'role': 'admin'});
      delegate.onStateChanged('initial_list', ['first', 'second']);

      final eng = LuaEngine(
        context: PluginContext(
          pluginId: 'test_state_table',
          storage: InMemoryPluginStorage(),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {},
        ),
        delegate: delegate,
      );

      eng.loadAndExecute('''
        local user = state.get("initial_user")
        local list = state.get("initial_list")
        state.set("user_name", user.name)
        state.set("list_item_1", list[1])
        state.set("new_table", {
          score = 100,
          tags = {"lua", "dart"}
        })
      ''');

      expect(delegate.getState('user_name'), 'Bob');
      expect(delegate.getState('list_item_1'), 'first');
      expect(delegate.getState('new_table'), isA<Map>());
      expect((delegate.getState('new_table') as Map)['score'], 100);
      expect((delegate.getState('new_table') as Map)['tags'], ['lua', 'dart']);
      eng.close();
    });

    test('StorageApi 支持丰富类型持久化与回调', () async {
      final storage = InMemoryPluginStorage();
      final delegate = MockLuaHostDelegate();
      final eng = LuaEngine(
        context: PluginContext(
          pluginId: 'test_storage_types',
          storage: storage,
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {PluginPermission.storage},
        ),
        delegate: delegate,
      );

      eng.loadAndExecute('''
        storage.set("num_key", 42, function(ok)
          state.set("set_num_ok", ok)
        end)
        storage.set("table_key", {title = "plugin", count = 3}, function(ok)
          state.set("set_table_ok", ok)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('set_num_ok') == true &&
          delegate.getState('set_table_ok') == true);

      expect(await storage.getValue('num_key'), 42);
      final storedTable = await storage.getValue('table_key');
      expect(storedTable, isA<Map>());
      expect((storedTable as Map)['title'], 'plugin');

      // 读取并通过回调接收
      eng.loadAndExecute('''
        storage.get("table_key", function(val)
          state.set("read_title", val.title)
          state.set("read_count", val.count)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('read_title') == 'plugin' &&
          delegate.getState('read_count') == 3);

      expect(delegate.getState('read_title'), 'plugin');
      expect(delegate.getState('read_count'), 3);

      eng.close();
    });
  });
}

class _SimpleStateDelegate implements LuaStateDelegate {
  final Map<String, dynamic> state;
  _SimpleStateDelegate(this.state);

  @override
  dynamic getState(String key) => state[key];

  @override
  Map<String, dynamic> getAllStates() => Map.unmodifiable(state);

  @override
  void onStateChanged(String key, dynamic value) => state[key] = value;
}

class _MockCustomDatabase implements PluginDatabase {
  final List<String> executedSqls = [];

  @override
  Future<Map<String, dynamic>> execute(String rawSql, List<dynamic> params,
      {bool inTransaction = false}) async {
    executedSqls.add(rawSql);
    return {'ok': true, 'affected': 1};
  }

  @override
  Future<Map<String, dynamic>> query(
      String rawSql, List<dynamic> params) async {
    return {'ok': true, 'rows': []};
  }

  @override
  Future<Map<String, dynamic>> batch(
      List<Map<String, dynamic>> statements) async {
    return {'ok': true, 'batchCount': statements.length};
  }

  @override
  Future<Map<String, dynamic>> flush() async {
    return {'ok': true};
  }

  @override
  void dispose() {}
}
