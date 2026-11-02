# Android 真机 QA 工具

本目录用于验证 example 的宿主检查、弹窗、下载进度、取消重试、校验与安装。工具不启动模拟器，必须明确传入设备 serial；真机 UI 操作还必须显式指定 `--allow-physical-device`。

## 工具职责

- `prepare_fixture.py`：在临时目录生成同包名、同调试签名的轻量版本 2 APK，附带不可压缩的小测试载荷，便于限速观察进度。使用现有 Gradle/Android SDK 离线构建。
- `server.py`：仅监听 localhost，提供可控 manifest、限速 APK、错误摘要与一次性 503；记录 JSONL 事件。
- `ui.py`：通过实时 UI XML 查找字段/按钮和控件边界，执行输入、点击、滚动及截图。读取 UI 树失败时只重试读取，不重复点击。开关可通过 `--set-checked true/false` 幂等设定状态。

## 真机复现

以下命令从 example 目录执行。`SERIAL` 表示用户明确授权的真机，不要省略 `-s` 去操作其他连接设备。

1. 构建/安装当前 example，使用本项目既有 Android 工具链；若系统要求安装确认，在手机上完成该应用的确认。
2. 生成升级 fixture：

   ```sh
   python3 tool/android_qa/prepare_fixture.py \
     --gradle /path/to/gradle-8.12/bin/gradle \
     --sdk /path/to/android/sdk \
     --java-home /path/to/jdk21
   ```

   stdout 给出 APK 路径、大小与摘要。当前工具使用 AGP 8.9.1、compileSdk 35；需存在相应离线缓存。安装前用 `apksigner verify --print-certs` 核对 fixture 和 example 的签名一致。

3. 在终端启动测试服务：

   ```sh
   python3 tool/android_qa/server.py --apk /path/to/fixture.apk \
     --port 8766 --log /tmp/upgrade-device-events.jsonl
   ```

4. 在另一个终端配置真机连接并打开 example：

   ```sh
   adb -s SERIAL reverse tcp:8766 tcp:8766
   adb -s SERIAL shell am start -n com.egeio.upgrade_kit_example/.MainActivity
   ```

5. 在 example 的 Host-controlled APK update 表单填写：
   - manifest：`http://127.0.0.1:8766/release/good`。
   - 当前构建号：`1`。
   - 下载路径：`/data/user/0/com.egeio.upgrade_kit_example/cache/qa-device.apk`，保证文件尚不存在。
6. 点击检查、确认下载，观察进度。可用本地控制接口改变测试服务行为：

   ```sh
   curl 'http://127.0.0.1:8766/control?delay=1'
   curl 'http://127.0.0.1:8766/control?delay=0.01'
   curl 'http://127.0.0.1:8766/control?delay=0&fail_next=1'
   ```

   `delay` 是每个 1 KiB 数据块后的延时秒数。取消后确认部分文件清理，点击重试完成下载。`fail_next=1` 只让下一次 APK 请求返回一次 503。
7. 校验失败可使用 `/release/bad`（错误摘要）和新文件名，或在下载完成后仅破坏本次 QA 文件，再点击 Verify and install。应显示校验失败并保持在 example。
8. 用正确摘要重新完整下载后点击安装，授权该测试应用的未知来源安装权限，返回后再次点击 Verify and install。完成手机系统的安装确认，再用系统包信息验证版本 2。

UI 自动化示例：

```sh
python3 tool/android_qa/ui.py \
  --adb /path/to/adb --serial SERIAL --allow-physical-device \
  --out /tmp/upgrade-ui-evidence --name upgrade-prompt \
  tap --text 'Check host service and prompt'
```

`fill --hint 'Host version manifest URL' --value URL` 可填写字段，`snapshot` 只取证，`key --value 4` 返回。不要根据截图猜测点击位置，也不要对安装器之外的手机应用发送操作。

## 测试后恢复

Fixture 会替换同包名的 Flutter example，只应对本次测试用 example 使用，不能用于生产应用。验证后重新安装原 Debug APK：

```sh
adb -s SERIAL install -r -d /path/to/original-app-debug.apk
adb -s SERIAL reverse --remove tcp:8766
```

`-d` 用于允许调试包从测试版本 2 恢复到原版本 1；保留应用数据。vivo 等 ROM 可能要求对恢复安装额外确认。恢复测试前的来源安装权限，删除仅本次创建的 QA 缓存文件，停止服务进程。不要卸载或清除其他应用的数据。

实际真机结果见仓库 `qa/2026-10-29-android-device/REPORT.md`。
