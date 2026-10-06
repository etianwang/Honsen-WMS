"""The only component allowed to launch or update Honsen WMS on Windows."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

APP_ID = "honsen.wms"
UPDATE_URL = "https://api.github.com/repos/etianwang/Honsen-WMS/releases/latest"
MUTEX_NAME = r"Global\HonsenUpdate-honsen_wms"


class RunnerError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def normalized(path: str | Path) -> str:
    return os.path.normcase(os.path.realpath(os.path.abspath(path)))


def write_result(path: str, payload: dict) -> None:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, destination)


def result_path(value: str | None, operation_id: str) -> str:
    base = Path(os.environ.get("LOCALAPPDATA", tempfile.gettempdir())) / "Honsen Program" / "UpdateResults"
    return value or str(base / APP_ID / f"{operation_id}.json")


def registry_record() -> dict:
    if os.name != "nt":
        raise RunnerError("HonsenUpdateRunner is supported on Windows only")
    import winreg

    values = ("AppId", "DisplayName", "Version", "InstallLocation", "ExecutablePath", "LauncherPath", "UpdateRunnerPath", "InstallScope", "Publisher", "UpdateManifestUrl", "UpdateUrl")
    key_path = rf"Software\Honsen Program\Apps\{APP_ID}"
    for root, scope in ((winreg.HKEY_LOCAL_MACHINE, "machine"), (winreg.HKEY_CURRENT_USER, "user")):
        for view, access in ((64, winreg.KEY_WOW64_64KEY), (32, winreg.KEY_WOW64_32KEY)):
            try:
                with winreg.OpenKey(root, key_path, 0, winreg.KEY_READ | access) as key:
                    record = {name: winreg.QueryValueEx(key, name)[0] for name in values}
            except FileNotFoundError:
                continue
            if record["AppId"] == APP_ID and record["InstallScope"] == scope:
                record["_scope"] = scope
                record["_view"] = view
                return record
    raise RunnerError("No valid honsen.wms registration was found")


def validate_install(record: dict, target_dir: str | None = None) -> dict:
    install = normalized(record["InstallLocation"])
    if target_dir and normalized(target_dir) != install:
        raise RunnerError("target-dir does not match the registered InstallLocation")
    manifest_path = Path(install) / "honsen.app.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RunnerError(f"Invalid honsen.app.json: {exc}") from exc
    executable = Path(install) / manifest.get("executable", "")
    runner = Path(install) / manifest.get("updateRunner", "")
    if manifest.get("appId") != APP_ID or manifest.get("updateManifestUrl") != UPDATE_URL:
        raise RunnerError("Manifest identity or update URL is invalid")
    if normalized(executable) != normalized(record["ExecutablePath"]) or not executable.is_file():
        raise RunnerError("Registered ExecutablePath does not match the installed main executable")
    if normalized(runner) != normalized(record["LauncherPath"]) or normalized(runner) != normalized(record["UpdateRunnerPath"]) or not runner.is_file():
        raise RunnerError("Registered runner path does not match the installed runner")
    if record["UpdateManifestUrl"] != UPDATE_URL or record["UpdateUrl"] != UPDATE_URL:
        raise RunnerError("Registered update URL is invalid")
    return {"install": install, "manifest": manifest, "executable": executable, "runner": runner}


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise RunnerError(f"Unable to read installer: {exc}") from exc
    return digest.hexdigest()


def file_version(path: Path) -> str:
    if os.name != "nt":
        raise RunnerError("File version verification is supported on Windows only")
    version = ctypes.windll.version
    size = version.GetFileVersionInfoSizeW(str(path), None)
    if not size:
        raise RunnerError(f"Missing Windows file version: {path}")
    buffer = ctypes.create_string_buffer(size)
    if not version.GetFileVersionInfoW(str(path), 0, size, buffer):
        raise RunnerError(f"Unable to read Windows file version: {path}")
    pointer = ctypes.c_void_p()
    length = ctypes.c_uint()
    if not version.VerQueryValueW(buffer, "\\", ctypes.byref(pointer), ctypes.byref(length)):
        raise RunnerError(f"Unable to query Windows file version: {path}")

    class FixedFileInfo(ctypes.Structure):
        _fields_ = [("signature", ctypes.c_uint32), ("struct_version", ctypes.c_uint32), ("file_ms", ctypes.c_uint32), ("file_ls", ctypes.c_uint32)]

    info = ctypes.cast(pointer, ctypes.POINTER(FixedFileInfo)).contents
    parts = [info.file_ms >> 16, info.file_ms & 0xFFFF, info.file_ls >> 16, info.file_ls & 0xFFFF]
    while len(parts) > 3 and parts[-1] == 0:
        parts.pop()
    return ".".join(map(str, parts))


def wait_for_wms(pid: int, executable: Path) -> None:
    if not pid:
        return
    kernel32 = ctypes.windll.kernel32
    process = kernel32.OpenProcess(0x00100000 | 0x1000 | 0x0001, False, pid)
    if not process:
        return  # The requested process has already exited.
    try:
        size = ctypes.c_uint(32768)
        image = ctypes.create_unicode_buffer(size.value)
        if not kernel32.QueryFullProcessImageNameW(process, 0, image, ctypes.byref(size)):
            raise RunnerError("Unable to verify the requested process path")
        if normalized(image.value) != normalized(executable):
            raise RunnerError("wait-pid is not the registered Honsen WMS process")
        if kernel32.WaitForSingleObject(process, 30000) == 0x102:
            if not kernel32.TerminateProcess(process, 0) or kernel32.WaitForSingleObject(process, 5000) == 0x102:
                raise RunnerError("Honsen WMS did not exit within 30 seconds")
    finally:
        kernel32.CloseHandle(process)


@contextmanager
def update_lock():
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if not handle:
        raise RunnerError("Unable to create update mutex")
    try:
        if kernel32.GetLastError() == 183:
            raise RunnerError("Another Honsen WMS update is already running")
        yield
    finally:
        kernel32.CloseHandle(handle)


def is_admin() -> bool:
    return bool(ctypes.windll.shell32.IsUserAnAdmin())


def run_installer(installer: str, install: str, log_path: str, machine_install: bool) -> int:
    arguments = ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", f"/DIR={install}", f"/LOG={log_path}"]
    if not machine_install or is_admin():
        return subprocess.run([installer, *arguments], check=False).returncode

    class ShellExecuteInfo(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_uint32), ("fMask", ctypes.c_ulong), ("hwnd", ctypes.c_void_p), ("lpVerb", ctypes.c_wchar_p), ("lpFile", ctypes.c_wchar_p), ("lpParameters", ctypes.c_wchar_p), ("lpDirectory", ctypes.c_wchar_p), ("nShow", ctypes.c_int), ("hInstApp", ctypes.c_void_p), ("lpIDList", ctypes.c_void_p), ("lpClass", ctypes.c_wchar_p), ("hkeyClass", ctypes.c_void_p), ("dwHotKey", ctypes.c_uint32), ("hIcon", ctypes.c_void_p), ("hProcess", ctypes.c_void_p)]

    info = ShellExecuteInfo()
    info.cbSize = ctypes.sizeof(info)
    info.fMask = 0x00000040  # SEE_MASK_NOCLOSEPROCESS
    info.lpVerb = "runas"
    info.lpFile = installer
    info.lpParameters = subprocess.list2cmdline(arguments)
    info.lpDirectory = str(Path(installer).parent)
    info.nShow = 0
    if not ctypes.windll.shell32.ShellExecuteExW(ctypes.byref(info)) or not info.hProcess:
        raise RunnerError("UAC elevation for the installer was declined or failed")
    try:
        ctypes.windll.kernel32.WaitForSingleObject(info.hProcess, 0xFFFFFFFF)
        exit_code = ctypes.c_uint32()
        if not ctypes.windll.kernel32.GetExitCodeProcess(info.hProcess, ctypes.byref(exit_code)):
            raise RunnerError("Unable to read elevated installer exit code")
        return exit_code.value
    finally:
        ctypes.windll.kernel32.CloseHandle(info.hProcess)


def operation_result(status: str, args: argparse.Namespace, from_version: str = "", to_version: str = "", **extra: object) -> dict:
    return {"appId": APP_ID, "operationId": args.operation_id, "status": status, "source": args.source, "fromVersion": from_version, "toVersion": to_version, "step": extra.pop("step", None), "installerExitCode": extra.pop("installerExitCode", None), "installerLogPath": extra.pop("installerLogPath", ""), "message": extra.pop("message", ""), "completedAtUtc": now(), **extra}


def launch(args: argparse.Namespace) -> dict:
    record = registry_record()
    state = validate_install(record)
    subprocess.Popen([str(state["executable"])], cwd=state["install"])
    return operation_result("success", args, record["Version"], record["Version"], installLocation=state["install"], executablePath=str(state["executable"]), message="应用已启动")


def relocate_and_run() -> int:
    operation_id = next((sys.argv[index + 1] for index, value in enumerate(sys.argv) if value == "--operation-id"), str(uuid.uuid4()))
    target = Path(tempfile.gettempdir()) / "Honsen Program" / "UpdateRunner" / operation_id / "HonsenUpdateRunner.exe"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(sys.executable, target)
    return subprocess.run([str(target), *sys.argv[1:], "--relocated"], check=False).returncode


def apply(args: argparse.Namespace) -> dict:
    if not getattr(sys, "frozen", False) and not args.relocated:
        raise RunnerError("apply must run from the packaged HonsenUpdateRunner.exe")
    if getattr(sys, "frozen", False) and not args.relocated:
        raise SystemExit(relocate_and_run())
    step = "validate"
    exit_code: int | None = None
    log_path = ""
    try:
        with update_lock():
            record = registry_record()
            old_version = record["Version"]
            state = validate_install(record, args.target_dir)
            if state["manifest"].get("version") != old_version:
                raise RunnerError("Manifest and registry versions differ before update")
            step = "sha256"
            if sha256(args.installer).lower() != args.sha256.lower():
                raise RunnerError("Installer SHA-256 does not match")
            step = "wait"
            wait_for_wms(args.wait_pid, state["executable"])
            step = "install"
            log_path = str(Path(tempfile.gettempdir()) / "Honsen Program" / "UpdateRunner" / args.operation_id / "installer.log")
            Path(log_path).parent.mkdir(parents=True, exist_ok=True)
            exit_code = run_installer(args.installer, state["install"], log_path, record["_scope"] == "machine")
            if exit_code != 0 or not Path(log_path).is_file():
                raise RunnerError("Inno Setup update failed")
            step = "verify"
            updated_record = registry_record()
            updated = validate_install(updated_record, state["install"])
            if updated_record["Version"] != args.expected_version or updated["manifest"].get("version") != args.expected_version or file_version(updated["executable"]) != args.expected_version:
                raise RunnerError("Updated version verification failed")
            if args.restart == "true":
                subprocess.Popen([str(updated["executable"])], cwd=updated["install"])
            return operation_result("success", args, old_version, args.expected_version, installLocation=updated["install"], executablePath=str(updated["executable"]), installerExitCode=exit_code, installerLogPath=log_path, message="更新完成")
    except (RunnerError, OSError) as exc:
        return operation_result("failed", args, old_version if "old_version" in locals() else "", args.expected_version, step=step, installerExitCode=exit_code, installerLogPath=log_path, message=str(exc))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    for name in ("launch", "apply"):
        command = commands.add_parser(name)
        command.add_argument("--app-id", required=True)
        command.add_argument("--source", required=True, choices=("app", "toolbox", "shell", "installer"))
        command.add_argument("--operation-id")
        command.add_argument("--result-path")
    launch_command = commands.choices["launch"]
    launch_command.add_argument("--wait-pid", type=int, default=0)
    apply_command = commands.choices["apply"]
    apply_command.add_argument("--wait-pid", type=int, required=True)
    apply_command.add_argument("--installer", required=True)
    apply_command.add_argument("--sha256", required=True)
    apply_command.add_argument("--target-dir", required=True)
    apply_command.add_argument("--expected-version", required=True)
    apply_command.add_argument("--restart", choices=("true", "false"), required=True)
    apply_command.add_argument("--relocated", action="store_true", help=argparse.SUPPRESS)
    return root


def main() -> int:
    args = parser().parse_args()
    if args.app_id != APP_ID:
        raise SystemExit("Unsupported app-id")
    if not args.operation_id:
        if args.source not in {"shell", "installer"}:
            raise SystemExit("--operation-id is required for app and toolbox operations")
        args.operation_id = str(uuid.uuid4())
    if not args.result_path:
        if args.source not in {"shell", "installer"}:
            raise SystemExit("--result-path is required for app and toolbox operations")
        args.result_path = result_path(None, args.operation_id)
    try:
        payload = apply(args) if args.command == "apply" else launch(args)
    except (RunnerError, OSError) as exc:
        payload = operation_result("failed", args, "", getattr(args, "expected_version", ""), step="validate", message=str(exc))
    write_result(args.result_path, payload)
    return 0 if payload["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
