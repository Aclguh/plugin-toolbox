---@meta
--- ==============================================================================
--- PluginToolbox 官方 Lua 运行时环境类型与 API 定义 (EmmyLua / LuaLS 格式)
--- 用于 VS Code, IntelliJ IDEA 等现代 IDE 智能补全、语法校验与悬停文档。
--- 版权所有 (c) 2026 PluginToolbox Team
--- ==============================================================================

--- 全局标准日志输出函数（重定向至宿主诊断控制台与 Android Logcat）
---@param ... any 需要打印的内容
function print(...) end

-- ==============================================================================
-- 1. state 响应式状态管理 API
-- ==============================================================================
---@class StateApi
state = {}

--- 获取指定键的当前状态值（支持点号深层路径例如 "user.profile.name"）
---@param key string 状态键名
---@return any
function state.get(key) end

--- 设置指定键的状态值，触发 DUI 局部精准刷新
---@param key string 状态键名
---@param value any 状态值
function state.set(key, value) end

--- 批量更新状态
---@param values table<string, any>
function state.setAll(values) end

--- 获取当前全部状态的浅拷贝只读表
---@return table<string, any>
function state.getAll() end

-- ==============================================================================
-- 2. clipboard 剪贴板 API
-- ==============================================================================
---@class ClipboardApi
clipboard = {}

--- 设置系统剪贴板文本
---@param text string 文本内容
function clipboard.set(text) end

--- 异步获取系统剪贴板文本
---@param callback fun(text: string|nil) 成功回调
function clipboard.get(callback) end

-- ==============================================================================
-- 3. storage 沙箱持久化键值存储 API
-- ==============================================================================
---@class StorageApi
storage = {}

--- 获取持久化键值
---@param key string
---@param callback fun(value: any)
function storage.get(key, callback) end

--- 写入持久化键值
---@param key string
---@param value any
---@param callback? fun(success: boolean)
function storage.set(key, value, callback) end

--- 删除指定持久化键
---@param key string
---@param callback? fun(success: boolean)
function storage.remove(key, callback) end

--- 清空插件在沙箱内的全部持久化数据
---@param callback? fun(success: boolean)
function storage.clear(callback) end

-- ==============================================================================
-- 4. network 现代 HTTP 网络请求 API (带 SSRF 与白名单保护)
-- ==============================================================================
---@class HttpResponse
---@field statusCode integer HTTP 状态码
---@field body string 响应文本
---@field headers table<string, string> 响应头
---@field ok boolean 是否成功 (2xx 状态码)

---@class HttpRequestOptions
---@field url string 请求目标 URL (需在 allowedDomains 白名单内)
---@field method? string "GET"|"POST"|"PUT"|"DELETE"|"PATCH" 等
---@field headers? table<string, string> 请求头
---@field body? string|table 请求体内容
---@field timeoutMs? integer 超时毫秒数 (默认 15000)

---@class NetworkApi
network = {}

--- 发起通用 HTTP 请求
---@param options HttpRequestOptions
---@param callback fun(res: HttpResponse)
function network.request(options, callback) end

--- 发起 GET 请求
---@param url string 目标地址
---@param callback fun(res: HttpResponse)
function network.get(url, callback) end

--- 发起 POST 请求
---@param url string 目标地址
---@param body any 请求载荷
---@param callback fun(res: HttpResponse)
function network.post(url, body, callback) end

-- ==============================================================================
-- 5. dialog & ui 交互与原生弹窗 API
-- ==============================================================================
---@class DialogApi
dialog = {}

--- 弹出轻提示 Toast
---@param message string
function dialog.toast(message) end

--- 弹出原生模态警告框
---@param title string 标题
---@param message string 内容
---@param callback? fun()
function dialog.alert(title, message, callback) end

--- 弹出原生确认弹窗
---@param title string 标题
---@param message string 内容
---@param callback fun(confirmed: boolean)
function dialog.confirm(title, message, callback) end

--- 弹出文本输入提示框
---@param options { title: string, hint?: string, defaultValue?: string }
---@param callback fun(text: string|nil)
function dialog.prompt(options, callback) end

--- 弹出单选列表框
---@param options { title: string, items: string[], initialIndex?: integer }
---@param callback fun(result: { index: integer, item: string }|nil)
function dialog.pickItem(options, callback) end

--- 弹出底部操作表 BottomSheet
---@param options { title: string, items: string[] }
---@param callback fun(result: { index: integer, item: string }|nil)
function dialog.bottomSheet(options, callback) end

--- 弹出日期选择器
---@param options { initialDate?: string, firstDate?: string, lastDate?: string }
---@param callback fun(dateStr: string|nil)
function dialog.pickDate(options, callback) end

--- 弹出时间选择器
---@param options { initialTime?: string }
---@param callback fun(timeStr: string|nil)
function dialog.pickTime(options, callback) end

--- 收起软键盘
function dialog.hideKeyboard() end

---@class UiApi
ui = {}

--- 隐藏软键盘
function ui.hideKeyboard() end

--- 触发触感振动反馈
---@param type? "light"|"medium"|"heavy"|"selection"|"vibrate"
function ui.haptic(type) end

---@class HapticApi
haptic = {}
---@param type? "light"|"medium"|"heavy"|"selection"|"vibrate"
function haptic.vibrate(type) end

-- ==============================================================================
-- 6. crypto, hash & codec 编解码与加解密 API
-- ==============================================================================
---@class HashApi
hash = {}
---@param text string
---@return string MD5 十六进制小写
function hash.md5(text) end
---@param text string
---@return string SHA-1 十六进制小写
function hash.sha1(text) end
---@param text string
---@return string SHA-256 十六进制小写
function hash.sha256(text) end
---@param text string
---@return string SHA-512 十六进制小写
function hash.sha512(text) end

---@class CodecApi
codec = {}
---@param text string
---@return string Base64 编码结果
function codec.base64Encode(text) end
---@param b64 string
---@return string Base64 解码文本
function codec.base64Decode(b64) end
---@param text string
---@return string URL 编码
function codec.urlEncode(text) end
---@param encoded string
---@return string URL 解码
function codec.urlDecode(encoded) end
---@param text string
---@return string 十六进制字符串
function codec.hexEncode(text) end
---@param hexStr string
---@return string 原始文本
function codec.hexDecode(hexStr) end

---@class CryptoApi
crypto = {}
--- AES-CBC 加密
---@param text string 待加密明文
---@param key string 密钥
---@param iv? string 初始化向量
---@return string Base64 密文
function crypto.aesEncrypt(text, key, iv) end
--- AES-CBC 解密
---@param encryptedBase64 string Base64 密文
---@param key string 密钥
---@param iv? string 初始化向量
---@return string 解密明文
function crypto.aesDecrypt(encryptedBase64, key, iv) end
--- 国密 SM3 散列
---@param text string
---@return string SM3 散列值
function crypto.sm3(text) end

-- ==============================================================================
-- 7. json, xml & yaml 数据解析与转换 API
-- ==============================================================================
---@class JsonApi
json = {}
---@param str string
---@return any
function json.decode(str) end
---@param value any
---@param pretty? boolean 是否美化格式
---@return string
function json.encode(value, pretty) end

-- ==============================================================================
-- 8. fs 沙箱文件系统 API (严格防范路径穿越)
-- ==============================================================================
---@class FsApi
fs = {}
--- 读取沙箱内文本文件
---@param path string 沙箱相对路径
---@param callback fun(content: string|nil, err: string|nil)
function fs.readText(path, callback) end
--- 写入文本到沙箱文件
---@param path string 沙箱相对路径
---@param content string 文本内容
---@param callback? fun(ok: boolean, err: string|nil)
function fs.writeText(path, content, callback) end
--- 检查文件或目录是否存在
---@param path string
---@param callback fun(exists: boolean)
function fs.exists(path, callback) end
--- 删除文件
---@param path string
---@param callback? fun(ok: boolean, err: string|nil)
function fs.delete(path, callback) end
--- 列出沙箱目录内容
---@param dirPath? string
---@param callback fun(list: string[]|nil, err: string|nil)
function fs.list(dirPath, callback) end

-- ==============================================================================
-- 9. task 并发计算与后台 Worker 调度 API
-- ==============================================================================
---@class TaskResult
---@field ok boolean
---@field result? any
---@field error? string

---@class TaskApi
task = {}
--- 在独立后台 Isolate 中执行 Lua 纯计算任务，不阻塞主 UI 线程
---@param script string 纯计算脚本代码 (可声明 function main(args) ... end)
---@param args? any 传入参数
---@param callback fun(res: TaskResult)
function task.run(script, args, callback) end

--- 并发执行多个后台计算任务
---@param taskList { script: string, args?: any, timeoutMs?: integer }[]
---@param callback fun(res: { ok: boolean, results: TaskResult[], error?: string })
function task.parallel(taskList, callback) end

-- ==============================================================================
-- 10. timer 定时器 API
-- ==============================================================================
---@class TimerApi
timer = {}
--- 延迟执行单次回调
---@param delayMs integer 毫秒数
---@param callback fun()
---@return integer timerId
function timer.setTimeout(delayMs, callback) end
--- 循环定时执行回调 (最小周期 16ms 防掉帧)
---@param intervalMs integer 毫秒数
---@param callback fun()
---@return integer timerId
function timer.setInterval(intervalMs, callback) end
--- 取消定时器
---@param timerId integer
function timer.clearTimeout(timerId) end
--- 取消周期定时器
---@param timerId integer
function timer.clearInterval(timerId) end

-- ==============================================================================
-- 11. system, device & hardware 硬件与系统能力 API
-- ==============================================================================
---@class SystemInfo
---@field os string
---@field platform string
---@field isAndroid boolean
---@field sdkVersion integer
---@field deviceModel string
---@field appVersion string

---@class SystemApi
system = {}
--- 获取系统与设备信息
---@param callback fun(info: SystemInfo)
function system.getInfo(callback) end
--- 获取电池电量与充电状态
---@param callback fun(battery: { level: integer, isCharging: boolean })
function system.getBattery(callback) end
--- 设置屏幕常亮 (需 screen 权限)
---@param keepOn boolean
function system.setKeepScreenOn(keepOn) end
--- 设置屏幕亮度 (0.0 ~ 1.0, 需 screen 权限)
---@param brightness number
function system.setBrightness(brightness) end

---@class TorchApi
torch = {}
--- 开关后置手电筒 (需 camera 权限)
---@param enabled boolean
function torch.set(enabled) end
--- 切换手电筒状态
function torch.toggle() end

---@class QrcodeApi
qrcode = {}
--- 生成二维码并返回 Base64 编码的 PNG 图片
---@param text string 二维码内容
---@return string base64Png
function qrcode.generate(text) end

---@class CameraApi
camera = {}
--- 扫码识别 (条形码与二维码，需 camera 权限)
---@param options? { prompt?: string }
---@param callback fun(code: string|nil)
function camera.scanBarcode(options, callback) end
--- 从本地图片解码二维码
---@param imagePath string 本地沙箱图片路径
---@param callback fun(code: string|nil)
function camera.decodeFromImage(imagePath, callback) end

---@class ShareApi
share = {}
--- 调用系统分享面板分享文本
---@param text string
function share.text(text) end
--- 分享沙箱内的本地文件
---@param filePath string
function share.file(filePath) end

---@class BiometricsApi
biometrics = {}
--- 生物识别指纹/人脸认证
---@param reason string 认证说明文案
---@param callback fun(authenticated: boolean)
function biometrics.authenticate(reason, callback) end

-- ==============================================================================
-- 12. ipc 跨插件通信与服务总线 API
-- ==============================================================================
---@class IpcApi
ipc = {}
--- 注册当前插件对外部暴露的 RPC 服务方法
---@param methodName string 服务名称
---@param handler fun(args: any): any 服务处理函数
function ipc.register(methodName, handler) end
--- 调用其他插件暴露的 RPC 服务
---@param targetPluginId string 目标插件 ID
---@param methodName string 服务名称
---@param args? any 参数
---@param callback fun(res: { ok: boolean, data?: any, error?: string })
function ipc.call(targetPluginId, methodName, args, callback) end
--- 广播跨插件应用级全局事件
---@param eventName string 事件名
---@param payload? any 负载数据
function ipc.emit(eventName, payload) end
--- 订阅跨插件应用级事件
---@param eventName string 事件名
---@param callback fun(payload: any)
function ipc.on(eventName, callback) end

-- ==============================================================================
-- 13. i18n 多语言本地化 API
-- ==============================================================================
---@class I18nApi
i18n = {}
--- 获取当前宿主语言代码 (例如 "zh" 或 "en")
---@return string
function i18n.getLocale() end
--- 根据当前宿主语言翻译对应字典中的文案
---@param translations table<string, string> 形如 { zh = "确定", en = "OK" }
---@param defaultText? string 缺省文本
---@return string
function i18n.t(translations, defaultText) end

-- ==============================================================================
-- 14. 扩展宿主 API 命名空间
-- ==============================================================================
---@class UtilApi
util = {}

---@class RegexApi
regex = {}

---@class ColorApi
color = {}

---@class ArchiveApi
archive = {}

---@class DocumentApi
document = {}

---@class MediaApi
media = {}

---@class ImageApi
image = {}

---@class VisionApi
vision = {}

---@class SensorApi
sensor = {}

---@class NotificationApi
notification = {}

---@class AudioApi
audio = {}

---@class SocketApi
socket = {}

---@class WebSocketApi
websocket = {}

---@class ScreenApi
screen = {}

---@class LocationApi
location = {}

---@class NfcApi
nfc = {}

---@class BluetoothApi
bluetooth = {}

---@class DatabaseApi
database = {}

---@class AiApi
ai = {}

