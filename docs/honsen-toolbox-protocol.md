# Honsen 工具箱应用识别

本应用的永久标识为 `honsen.wms`，产品名为 **Honsen WMS**，当前发布版本为 `1.2.1`。

桌面构建会生成 Inno Setup 安装器 `dist/HonsenWMS-<version>-Setup.exe`，它保留 Windows 控制面板卸载项，并在安装、升级、卸载时维护 Honsen 工具箱协议。构建环境需安装 Inno Setup 6。

运行安装器并选择“当前用户”或“所有用户”安装范围即可。升级时运行新版安装器；卸载时通过 Windows“已安装的应用”卸载，安装器会删除对应范围的 Honsen Program 注册表项。

便携包仍会在 `dist/` 生成以下文件：

- `honsen.app.json`：与主程序 exe 同目录的 UTF-8 识别文件。
- `Install-HonsenWms.ps1`：便携包的安装、升级和卸载脚本。

以下命令仅用于便携包的安装：

```powershell
.\Install-HonsenWms.ps1 -Action Install -Scope user
```

全电脑安装需以管理员身份运行：

```powershell
.\Install-HonsenWms.ps1 -Action Install -Scope machine
```

重复执行安装命令即为升级：它会保留 `honsen.wms` 与主程序名称，并同步覆盖目标 exe、`honsen.app.json` 和对应范围的注册表值。卸载时使用同一安装范围：

```powershell
.\Install-HonsenWms.ps1 -Action Uninstall -Scope user
```

安装后验证：

```powershell
Get-ItemProperty "HKCU:\Software\Honsen Program\Apps\honsen.wms"
Get-Content "$env:LOCALAPPDATA\Programs\Honsen WMS\honsen.app.json" -Encoding UTF8
```

机器范围安装时，将 `HKCU` 换为 `HKLM`，并检查 `$env:ProgramFiles\Honsen WMS`。
