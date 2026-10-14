import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_dialog_service.dart';
import 'package:plugin_toolbox/src/plugin_host/desktop_simulation_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestHost(Widget Function(BuildContext context) builder) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: builder),
      ),
    );
  }

  testWidgets('showToast 显示浮动 SnackBar', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () => PluginDialogService.showToast(context, '测试轻提示'),
            child: const Text('触发 Toast'),
          )),
    );

    await tester.tap(find.text('触发 Toast'));
    await tester.pump();

    expect(find.text('测试轻提示'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('showAlert 弹出警告弹窗并点击确定关闭', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () => PluginDialogService.showAlert(
                context, '警告标题', '警告详细信息内容'),
            child: const Text('打开警告'),
          )),
    );

    await tester.tap(find.text('打开警告'));
    await tester.pumpAndSettle();

    expect(find.text('警告标题'), findsOneWidget);
    expect(find.text('警告详细信息内容'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('警告标题'), findsNothing);
  });

  testWidgets('showConfirm 支持确定与取消分支', (WidgetTester tester) async {
    bool? confirmedResult;

    await tester.pumpWidget(
      buildTestHost((context) => Column(
            children: [
              ElevatedButton(
                onPressed: () async {
                  confirmedResult = await PluginDialogService.showConfirm(
                      context, '确认操作', '是否继续执行？');
                },
                child: const Text('打开确认'),
              ),
            ],
          )),
    );

    // 1. 取消分支
    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();

    expect(find.text('确认操作'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(confirmedResult, isFalse);

    // 2. 确定分支
    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(confirmedResult, isTrue);
  });

  testWidgets('showPrompt 支持输入默认值与确认返回值', (WidgetTester tester) async {
    String? promptResult;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              promptResult = await PluginDialogService.showPrompt(
                context,
                title: '请输入名称',
                hint: '自定义名称',
                defaultValue: '默认文本',
              );
            },
            child: const Text('打开输入框'),
          )),
    );

    // 1. 测试直接确认默认值
    await tester.tap(find.text('打开输入框'));
    await tester.pumpAndSettle();

    expect(find.text('请输入名称'), findsOneWidget);
    expect(find.text('默认文本'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(promptResult, '默认文本');

    // 2. 测试输入新文本并确认
    await tester.tap(find.text('打开输入框'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '修改后的文本');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(promptResult, '修改后的文本');

    // 3. 测试取消输入
    await tester.tap(find.text('打开输入框'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(promptResult, isNull);
  });

  testWidgets('showPickItem 弹出选项列表并返回选中项', (WidgetTester tester) async {
    Map<String, dynamic>? picked;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              picked = await PluginDialogService.showPickItem(
                context,
                title: '请选择分类',
                items: ['选项一', '选项二', '选项三'],
              );
            },
            child: const Text('打开选择项'),
          )),
    );

    await tester.tap(find.text('打开选择项'));
    await tester.pumpAndSettle();

    expect(find.text('请选择分类'), findsOneWidget);
    expect(find.text('选项二'), findsOneWidget);

    await tester.tap(find.text('选项二'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!['index'], 1);
    expect(picked!['text'], '选项二');
  });

  testWidgets('showBottomSheet 弹出底部面板并返回选中项', (WidgetTester tester) async {
    Map<String, dynamic>? picked;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              picked = await PluginDialogService.showBottomSheet(
                context,
                title: '底部操作项',
                items: ['动作 A', '动作 B'],
              );
            },
            child: const Text('打开面板'),
          )),
    );

    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();

    expect(find.text('底部操作项'), findsOneWidget);
    expect(find.text('动作 B'), findsOneWidget);

    await tester.tap(find.text('动作 B'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!['index'], 1);
    expect(picked!['text'], '动作 B');
  });

  testWidgets('pickDate 支持日期选择与容错解析', (WidgetTester tester) async {
    String? selectedDate;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              selectedDate = await PluginDialogService.pickDate(
                context,
                initialDate: '2026-10-14',
                firstDate: '2020-01-01',
                lastDate: '2030-12-31',
              );
            },
            child: const Text('选择日期'),
          )),
    );

    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();

    // 点击日历确认按钮
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(selectedDate, isNotNull);
    expect(selectedDate, contains('2026-10-14'));
  });

  testWidgets('pickTime 支持时间选择与容错解析', (WidgetTester tester) async {
    String? selectedTime;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              selectedTime = await PluginDialogService.pickTime(
                context,
                initialTime: '14:30',
              );
            },
            child: const Text('选择时间'),
          )),
    );

    await tester.tap(find.text('选择时间'));
    await tester.pumpAndSettle();

    // 点击时间选择器确认按钮
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(selectedTime, isNotNull);
    expect(selectedTime, '14:30');
  });

  testWidgets('DesktopSimulationAdapter 桌面环境扫码降级模拟输入', (WidgetTester tester) async {
    String? simulatedCode;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              simulatedCode =
                  await DesktopSimulationAdapter.simulateScanBarcode(context);
            },
            child: const Text('桌面扫码'),
          )),
    );

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    await tester.tap(find.text('桌面扫码'));
    await tester.pumpAndSettle();

    if (isDesktop) {
      expect(find.text('扫码识别 (桌面模拟)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'MOCK_QR_CODE_123');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(simulatedCode, 'MOCK_QR_CODE_123');
    } else {
      expect(simulatedCode, isNull);
    }
  });

  testWidgets('DesktopSimulationAdapter 桌面环境图片二维码识别模拟输入', (WidgetTester tester) async {
    String? simulatedCode;

    await tester.pumpWidget(
      buildTestHost((context) => ElevatedButton(
            onPressed: () async {
              simulatedCode =
                  await DesktopSimulationAdapter.simulateDecodeBarcode(context);
            },
            child: const Text('桌面图片识别'),
          )),
    );

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    await tester.tap(find.text('桌面图片识别'));
    await tester.pumpAndSettle();

    if (isDesktop) {
      expect(find.text('图片二维码识别 (桌面模拟)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'IMAGE_BARCODE_DATA');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(simulatedCode, 'IMAGE_BARCODE_DATA');
    } else {
      expect(simulatedCode, isNull);
    }
  });
}
