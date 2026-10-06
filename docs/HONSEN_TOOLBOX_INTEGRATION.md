# Honsen 工具箱集成

| 项目 | 值 |
| --- | --- |
| appId | `honsen.wms` |
| MainExe | `Honsen海外仓库管理同步版.exe` |
| 更新 Runner | `HonsenUpdateRunner.exe` |
| Release 安装包 | `HonsenWMS-<version>-Setup.exe` 与同名 `.sha256` |
| 更新源 | `https://api.github.com/repos/etianwang/Honsen-WMS/releases/latest` |

安装器默认目录为 `{autopf}\Honsen Program\Honsen WMS`。工具箱传入 `/DIR` 时原样使用；如现有 `honsen.wms` 注册记录指向另一目录，安装器会停止，禁止创建第二份安装。

## 注册表与描述文件

安装器按权限写入 `HKLM` 或 `HKCU\Software\Honsen Program\Apps\honsen.wms`，包含：`AppId`、`DisplayName`、`Version`、`InstallLocation`、`ExecutablePath`、`LauncherPath`、`UpdateRunnerPath`、`UpdateManifestUrl`、`UpdateUrl`、`InstallScope`、`Publisher`。`honsen.app.json` 与主程序同目录，以 UTF-8 写入，并包含相同版本、主程序文件名、Runner 文件名和更新源。

标准 Inno Setup 卸载登记保留在 Windows 卸载列表中；静默卸载支持 `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-`。卸载仅删除本应用的安装目录和精确匹配安装目录的 `honsen.wms` 注册项。

## Runner 命令

```text
HonsenUpdateRunner.exe launch --app-id honsen.wms --source toolbox --wait-pid 0 --operation-id <GUID> --result-path <JSON>
HonsenUpdateRunner.exe apply --source toolbox --app-id honsen.wms --wait-pid <PID> --installer <Setup.exe> --sha256 <SHA-256> --target-dir <InstallLocation> --expected-version <version> --restart false --operation-id <GUID> --result-path <JSON>
```

`launch` 只校验本机注册信息和 manifest 后启动主程序，不联网。`apply` 不下载任何文件；它只处理调用方已下载、已校验的安装包。Runner 会复制自身到 `%TEMP%\Honsen Program\UpdateRunner\<GUID>`、取得全局互斥锁、校验 SHA-256、等待/校验 WMS 进程，并在机器范围安装需要权限时自行触发 UAC，再校验版本、路径和 JSON 后原子写入调用方指定的结果 JSON。

结果文件必须由调用方传入；推荐路径为 `%LOCALAPPDATA%\Honsen Program\UpdateResults\honsen.wms\<GUID>.json`。成功和失败均使用跨项目协议规定的 `fromVersion`、`toVersion`、`step`、`installerExitCode`、`installerLogPath`、`message`、`completedAtUtc` 字段。

## 验证结果

| 场景 | 结果 |
| --- | --- |
| Windows CI 编译 | 待 `v1.2.4` 的最新协议修复提交完成后复核。 |
| 首次静默安装到指定目录 | 通过：`/DIR` 指向工作区测试目录后，HKCU 注册表、主 EXE、Runner 和 UTF-8 manifest 均存在且一致。 |
| Runner `apply` | 已完成静态验证；需在 `v1.2.4` 的受控 Windows 环境按上面的命令复测。 |
| 静默卸载 | 通过：Inno `unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` 移除了测试目录及 `honsen.wms` 的 HKCU 注册项。 |
| 未确认不更新 | 通过设计：WMS 与 Runner 均无网络下载代码；只有工具箱显式调用 `apply` 才会进入安装路径。 |
| launch 不自动更新 | 通过代码检查：`launch` 仅读取注册信息/manifest 并启动主 EXE，不访问网络。 |

安装后可执行：

```powershell
Get-ItemProperty 'HKLM:\Software\Honsen Program\Apps\honsen.wms'
Get-Content '<InstallLocation>\honsen.app.json' -Encoding UTF8
```
