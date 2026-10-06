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

`launch` 只校验本机注册信息和 manifest 后启动主程序，不联网。`apply` 不下载任何文件；它只处理工具箱已下载、已校验并经用户两次确认后的安装包。Runner 会复制自身到 `%TEMP%\Honsen Program\UpdateRunner\<GUID>`、取得全局互斥锁、校验 SHA-256、等待/校验 WMS 进程、静默运行安装器，并校验版本、路径和 JSON 后原子写入结果 JSON。

## 验证结果

- JSON、版本资源生成器和 Runner 均通过 Python 语法检查。
- Inno 脚本包含唯一目录、注册表、Runner 快捷方式和静默卸载逻辑；需要在 Windows CI 的 Inno Setup 环境做最终编译验证。
- 未实现后台更新检查、下载或自动安装；WMS 启动路径不会访问网络。

安装后可执行：

```powershell
Get-ItemProperty 'HKLM:\Software\Honsen Program\Apps\honsen.wms'
Get-Content '<InstallLocation>\honsen.app.json' -Encoding UTF8
```
