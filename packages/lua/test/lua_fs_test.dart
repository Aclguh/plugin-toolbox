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
  group('Lua Fs & Archive Host APIs', () {
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

    test('FsApi 沙箱文件读写、罗列与路径穿越拦截', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. 路径穿越拦截
      expect(
        () => fsEngine.loadAndExecute('fs.readFile("../../etc/passwd")'),
        throwsException,
      );

      // 2. 正常写入与读取
      fsEngine.loadAndExecute('''
        fs.writeFile("sub/test.txt", "hello sandbox")
        local content = fs.readFile("sub/test.txt")
        state.set("read_content", content)
        state.set("file_exists", fs.exists("sub/test.txt"))
        state.set("not_exists", fs.exists("no_such.txt"))
        
        local stat = fs.stat("sub/test.txt")
        state.set("file_size", stat.size)
        state.set("is_dir", stat.isDirectory)

        local list = fs.listFiles("sub")
        state.set("list_len", #list)
        state.set("list_first", list[1])

        fs.remove("sub/test.txt")
        state.set("after_remove_exists", fs.exists("sub/test.txt"))
      ''');

      expect(delegate.getState('read_content'), 'hello sandbox');
      expect(delegate.getState('file_exists'), true);
      expect(delegate.getState('not_exists'), false);
      expect(delegate.getState('file_size'), 'hello sandbox'.length);
      expect(delegate.getState('is_dir'), false);
      expect(delegate.getState('list_len'), 1);
      expect(delegate.getState('list_first'), 'test.txt');
      expect(delegate.getState('after_remove_exists'), false);
    });

    test('FsApi saveToGallery 与 exportFile 保存与导出', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_export_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final imgFile = File('${tempDir.path}/pic.png')
        ..writeAsStringSync('fake-png-data');
      final docFile = File('${tempDir.path}/data.csv')
        ..writeAsStringSync('col1,col2');

      final fsCtx = PluginContext(
        pluginId: 'fs_export_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. 非图片格式拒绝存入相册
      expect(
        () => fsEngine.loadAndExecute('fs.saveToGallery("data.csv")'),
        throwsException,
      );

      // 2. 正常保存图片到相册
      fsEngine.loadAndExecute('''
        fs.saveToGallery("pic.png", function(ok)
          state.set("gallery_saved", ok)
        end)
      ''');

      // 3. 导出文件到系统
      fsEngine.loadAndExecute('''
        fs.exportFile("data.csv", "my_export.csv", function(ok)
          state.set("exported_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.savedGalleryPath, imgFile.path);
      expect(delegate.getState('gallery_saved'), true);
      expect(delegate.exportedFilePath, docFile.path);
      expect(delegate.exportedFileDefaultName, 'my_export.csv');
      expect(delegate.getState('exported_ok'), true);
    });

    test('FsApi 异步非阻塞读写 (readFile, writeFile, readFileAsync, writeFileAsync)',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_async_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_async_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. fs.writeFile 带 callback
      fsEngine.loadAndExecute('''
        fs.writeFile("async_1.txt", "async hello 1", function(ok, err)
          state.set("write_1_ok", ok)
          fs.readFile("async_1.txt", function(content, err)
            state.set("read_1_content", content)
          end)
        end)
      ''');

      // 2. fs.writeFileAsync 与 fs.readFileAsync
      fsEngine.loadAndExecute('''
        fs.writeFileAsync("async_2.txt", "async hello 2", function(ok, err)
          state.set("write_2_ok", ok)
          fs.readFileAsync("async_2.txt", function(content, err)
            state.set("read_2_content", content)
          end)
        end)
      ''');

      // 3. 读取不存在文件的异步错误回调
      fsEngine.loadAndExecute('''
        fs.readFileAsync("not_exist.txt", function(content, err)
          state.set("read_err_content", content == nil)
          state.set("read_err_msg", err)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('write_1_ok') != null &&
          delegate.getState('read_1_content') != null &&
          delegate.getState('write_2_ok') != null &&
          delegate.getState('read_2_content') != null &&
          delegate.getState('read_err_content') != null);
      expect(delegate.getState('write_1_ok'), true);
      expect(delegate.getState('read_1_content'), 'async hello 1');
      expect(delegate.getState('write_2_ok'), true);
      expect(delegate.getState('read_2_content'), 'async hello 2');
      expect(delegate.getState('read_err_content'), true);
      expect(delegate.getState('read_err_msg'), contains('文件不存在'));
    });

    test('FsApi 扩展: readHex, writeHex, copy, move 与 fileSize', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_ext_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_ext_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      fsEngine.loadAndExecute('''
        -- 写入十六进制数据 (对应 ASCII: "Antigravity")
        -- "416e746967726176697479"
        local ok = fs.writeHex("test_bin.dat", "416e746967726176697479")
        state.set("write_ok", ok)
        state.set("bin_size", fs.fileSize("test_bin.dat"))
        state.set("read_hex", fs.readHex("test_bin.dat"))
        state.set("read_hex_sub", fs.readHex("test_bin.dat", 0, 4))

        -- 测试沙箱内复制与移动
        fs.copy("test_bin.dat", "copy_bin.dat")
        state.set("copy_exists", fs.exists("copy_bin.dat"))

        fs.move("copy_bin.dat", "moved_bin.dat")
        state.set("moved_exists", fs.exists("moved_bin.dat"))
        state.set("old_exists", fs.exists("copy_bin.dat"))
      ''');

      expect(delegate.getState('write_ok'), isTrue);
      expect(delegate.getState('bin_size'), 11);
      expect(delegate.getState('read_hex'), '416e746967726176697479');
      expect(delegate.getState('read_hex_sub'), '416e7469');
      expect(delegate.getState('copy_exists'), isTrue);
      expect(delegate.getState('moved_exists'), isTrue);
      expect(delegate.getState('old_exists'), isFalse);
    });

    test('FsApi 扩展: pickFile, writeBase64, readBase64 与 hash', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_hash_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_hash_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      delegate.pickedFileResult = 'data/mock_file.txt';
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      fsEngine.loadAndExecute('''
        -- 写入 Base64 (对应 ASCII: "Hello PluginToolbox")
        -- SGVsbG8gUGx1Z2luVG9vbGJveA==
        local ok = fs.writeBase64("hello.txt", "SGVsbG8gUGx1Z2luVG9vbGJveA==")
        state.set("b64_write_ok", ok)
        state.set("b64_read", fs.readBase64("hello.txt"))

        -- 计算各种哈希
        local md5_val = fs.hash("hello.txt", "md5")
        local sha1_val = fs.hash("hello.txt", "sha1")
        local sha256_val = fs.hash("hello.txt", "sha256")
        local crc_val = fs.hash("hello.txt", "crc32")
        state.set("file_md5", md5_val)
        state.set("file_sha1", sha1_val)
        state.set("file_sha256", sha256_val)
        state.set("file_crc32", crc_val)

        -- 全量信息表
        local meta = fs.hash("hello.txt")
        state.set("meta_name", meta.name)
        state.set("meta_size", meta.size)
        state.set("meta_ext", meta.extension)
        state.set("meta_md5", meta.md5)

        -- pickFile 回调
        fs.pickFile(function(path)
          state.set("picked_path", path)
        end)
      ''');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(delegate.getState('b64_write_ok'), isTrue);
      expect(delegate.getState('b64_read'), 'SGVsbG8gUGx1Z2luVG9vbGJveA==');
      expect(delegate.getState('file_md5'), isNotEmpty);
      expect(delegate.getState('file_sha1'), isNotEmpty);
      expect(delegate.getState('file_sha256'), isNotEmpty);
      expect(delegate.getState('file_crc32'), isNotEmpty);
      expect(delegate.getState('meta_name'), 'hello.txt');
      expect(delegate.getState('meta_size'), 19);
      expect(delegate.getState('meta_ext'), 'txt');
      expect(delegate.getState('meta_md5'), delegate.getState('file_md5'));
      expect(delegate.getState('picked_path'), 'data/mock_file.txt');
    });

    test('ArchiveApi: zip, list 与 unzip', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_archive_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final arcCtx = PluginContext(
        pluginId: 'archive_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final arcEngine = LuaEngine(context: arcCtx, delegate: delegate);

      arcEngine.loadAndExecute('''
        -- 准备测试文件
        fs.writeFile("sub/f1.txt", "hello")
        fs.writeFile("sub/f2.txt", "world")

        -- 压缩目录
        local zipOk = archive.zip("sub", "bundle.zip")
        state.set("zip_ok", zipOk)

        -- 读取条目列表
        local list = archive.list("bundle.zip")
        state.set("list_len", #list)

        -- 解压到新目录
        local unzipOk = archive.unzip("bundle.zip", "unpacked")
        state.set("unzip_ok", unzipOk)
        state.set("f1_content", fs.readFile("unpacked/f1.txt"))
        state.set("f2_content", fs.readFile("unpacked/f2.txt"))
      ''');

      expect(delegate.getState('zip_ok'), isTrue);
      expect(delegate.getState('list_len'), 2);
      expect(delegate.getState('unzip_ok'), isTrue);
      expect(delegate.getState('f1_content'), 'hello');
      expect(delegate.getState('f2_content'), 'world');
    });

    test('FsApi: 沙箱存储配额检测超限拒绝写入', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ptx_lua_quota_test');
      // 配额设为 0MB，任何写入均被拒绝
      final quotaCtx = PluginContext(
        pluginId: 'quota_fs_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        storageQuotaMb: 0,
        grantedPermissions: {PluginPermission.storage},
      );
      final quotaEngine = LuaEngine(context: quotaCtx, delegate: delegate);

      expect(
        () => quotaEngine.loadAndExecute('fs.writeFile("test.txt", "hello")'),
        throwsException,
      );

      quotaEngine.close();
      await tempDir.delete(recursive: true);
    });

    test('fs.hashAsync 与 fs.hash 异步后台 Isolate 哈希计算', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ptx_fs_hash_test_');
      final ctx = PluginContext(
        pluginId: 'hash_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.storage},
      );
      final eng = LuaEngine(context: ctx, delegate: delegate);

      final sampleFile = File('${tempDir.path}/hello.txt');
      await sampleFile.writeAsString('Hello Plugin Toolbox!');

      eng.loadAndExecute('''
        fs.hash("hello.txt", "sha256", function(res, err)
          state.set("sha256_result", res)
        end)
        fs.hashAsync("hello.txt", function(res, err)
          state.set("table_size", res.size)
          state.set("table_md5", res.md5)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('sha256_result') != null &&
          delegate.getState('table_md5') != null);

      expect(delegate.getState('sha256_result'), isNotEmpty);
      expect(delegate.getState('table_size'), 21);
      expect(delegate.getState('table_md5'), isNotEmpty);

      eng.close();
      await tempDir.delete(recursive: true);
    });
  });
}
