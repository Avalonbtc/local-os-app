# RigDeck App（local-os-app）

RigDeck 矿场管理的手机 App，Flutter 编写，一套代码出 Android 和 iOS。界面按「RigDeck App 原型」设计稿实现；数据直接来自主控现有的 REST API（`/api/v1`），不需要改主控即可使用。

## 运行

```bash
flutter pub get
flutter run                      # 连着的手机或模拟器
flutter run --profile            # 看真实帧率用 profile，debug 模式本身就慢
flutter build apk --release      # Android 安装包
flutter build ipa                # iOS（需要 Mac + Xcode + Apple 开发者账号）
```

登录页可以：

- **账号密码**：和主控网页同一个账号，会话 12 小时，过期后回到登录页。
- **API 令牌**：主控网页 设定 → AI / API 令牌 创建，不过期、可随时撤销，适合长期放在手机上。
- **先看看演示数据**：不连主控，用内置的演示矿场（24 台）。`--dart-define=DEMO_MACHINES=1000` 可以模拟 1000 台。

凭据存在系统钥匙串 / Keystore（flutter_secure_storage）。主控地址可以是局域网 `http://` 地址或经 VPN（Tailscale、WireGuard）访问的地址；Android 已允许明文 HTTP，iOS 允许本地网络明文。自签名 HTTPS 证书暂不支持。

## 这一版有什么

| 页面 | 内容 |
|---|---|
| 总览 | 矿机数（在线 / 离线 / 矿池离线）、按币种算力、软件功耗、预估电费、本次打开以来的实时算力曲线、需要处理的矿机 |
| 矿机 | 搜索、状态筛选（全部 / 在线 / 掉线 / 矿池离线 / 有问题）、长按多选批量操作：应用飞行表、启动 / 停止 / 重启矿工、BMC 开机 / 关机 / 强制重启 / 强制断电 |
| 矿机详情 | 概述（矿池离线原因、算力、温度、功耗、份额、硬件与连接）、矿工（单实例启停重启、矿工日志）、统计（1 小时–30 天的算力、温度、功耗曲线）、活动（运行层事件、任务、操作记录）、电源（BMC 状态、传感器、电源操作） |
| 飞行表 | 列表、在用台数、选择矿机应用 |
| 通知 | 离线 / 恢复通知（主控需包含 offline-alerts 分支），App 打开时有新通知会在底部弹出提示 |
| 更多 | 任务进度（可取消）、钱包、矿场设定与离线判定阈值、令牌与审计记录、退出登录 |

还没有的（在主控网页完成）：添加矿机、编辑飞行表、超频、BIOS、终端、新建令牌。锁屏推送需要主控增加推送服务（APNs / FCM），下一步做。

## 性能做法

目标是滑动、切页、动画都稳定 60/120 fps：

- **重活不在 UI 线程**：矿机列表的 JSON 解析和每台矿机的状态计算在后台 isolate（`Isolate.run`）完成，UI 只换上算好的快照。1000 台矿机每 10 秒刷新一次也不会卡帧。历史曲线同样在后台解析，并压缩到最多 240 个点（30 天分钟数据原本有 43 200 点）。
- **只重建需要的部分**：没有全局状态库，页面各自监听自己的 store（`ListenableBuilder`）；刷新只重建监听这份数据的页面，切换底部标签用 `IndexedStack` 保留页面，不重建、不丢滚动位置。
- **列表固定行高**：矿机列表 `ListView.builder` + `itemExtent`，只构建屏幕上的行，不测量行高。
- **绘制简单**：卡片用边框不用阴影和模糊（阴影、模糊需要额外的离屏合成）；曲线用 `CustomPainter` 直接画，包在 `RepaintBoundary` 里，数据没变不重画；点击水波纹用不需要编译着色器的 `InkRipple`。
- **后台不刷新**：App 切到后台立即停止轮询，回到前台再开始。
- **数字等宽**：数字用等宽字形（tabular figures），每 10 秒刷新时不会左右跳动、不触发多余的重排。

### 怎么量

```bash
# 帧耗时：1000 台演示矿机，滚动、切换标签、进出详情页；结果在 build/scroll_1000.timeline_summary.json
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart -d <设备>
```

看 `average_frame_build_time_millis`、`90th/99th_percentile_frame_rasterizer_time_millis` 和 `missed_frame_build_budget_count`：60 Hz 每帧预算 16.7 ms，120 Hz 是 8.3 ms。

2026-10-22 在 Windows 桌面（profile，1000 台演示矿机，期间后台刷新照常进行）实测 190 帧：

| | 平均 | 90% | 99% | 最差 | 超出预算 |
|---|---|---|---|---|---|
| 构建（UI 线程） | 0.19 ms | 0.45 ms | 1.54 ms | 2.57 ms | 0 |
| 光栅化（GPU 线程） | 0.52 ms | 0.89 ms | 1.02 ms | 1.06 ms | 0 |

桌面 CPU/GPU 比手机快，手机上的绝对值会更高，但离 8.3 ms 还有很大余量。还没有在真机上测过：拿到手机后用上面的命令跑一次（`-d` 换成手机的设备 ID）。

## 测试

```bash
flutter analyze
flutter test        # 数据计算（含 1000 台）、格式化、演示矿场完整走查、320pt 小屏 + 130% 字号不溢出
```

## 目录

```
lib/
  main.dart              入口、主题、登录状态切换
  theme.dart             颜色与主题（与主控网页一致的深色 + 琥珀色）
  api/client.dart        HTTP 客户端：会话 Cookie + CSRF 或 Bearer 令牌、主控时钟偏移、提交任务
  api/models.dart        数据模型与纯函数（buildFleet、buildHistory），可在后台 isolate 运行
  data/session.dart      登录、退出、凭据保存
  data/stores.dart       矿场与通知的定时刷新
  data/demo_backend.dart 演示矿场（与真实 API 同样的路径和 JSON）
  ui/                    各页面
test/                    单元测试与界面测试
integration_test/        帧耗时测试
```
