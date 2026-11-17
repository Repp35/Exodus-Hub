"""StyLua configuration, discovery and bounded command execution."""
from __future__ import annotations
import argparse
import errno
import os
import platform
import re
import shutil
import subprocess
from pathlib import Path
from typing import Iterable, Sequence

from .rules import FormatterError

TOOLS_ROOT = Path(__file__).resolve().parents[1]
HUB_ROOT = TOOLS_ROOT.parent
RESOURCE_ROOT = Path(__file__).resolve().parent / "resources"
DEFAULT_CONFIG = RESOURCE_ROOT / "stylua.toml"

def integer_stylua_setting(config: Path, key: str, fallback: int) -> int:
    pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(\d+)\s*(?:#.*)?$")
    for line in config.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("["):
            break
        match = pattern.match(line)
        if match:
            return int(match.group(1))
    return fallback

def string_stylua_setting(config: Path, key: str, fallback: str) -> str:
    pattern = re.compile(rf'^\s*{re.escape(key)}\s*=\s*"([^"]+)"\s*(?:#.*)?$')
    for line in config.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("["):
            break
        match = pattern.match(line)
        if match:
            return match.group(1)
    return fallback

def find_stylua() -> str:
    machine = platform.machine().lower()
    machine = {"amd64": "x86_64", "arm64": "aarch64"}.get(machine, machine)
    system = {
        "Linux": "linux",
        "Darwin": "macos",
        "Windows": "windows",
    }.get(platform.system())

    if system:
        suffix = ".exe" if system == "windows" else ""
        for filename in (f"stylua-{system}-{machine}{suffix}", f"stylua{suffix}"):
            bundled = RESOURCE_ROOT / filename
            if bundled.is_file() and os.access(bundled, os.X_OK):
                return str(bundled)

    installed = shutil.which("stylua")
    if installed:
        return installed

    raise FormatterError(
        "StyLua não encontrado. Use o executável desta pasta ou instale o StyLua no PATH."
    )

def make_stylua_command(
    executable: str,
    config: Path,
    staged_files: Sequence[Path],
    args: argparse.Namespace,
) -> list[str]:
    thread_count = args.threads
    if thread_count is None:
        thread_count = min(8, max(1, os.cpu_count() or 3), len(staged_files))
    if thread_count < 1:
        raise FormatterError("--threads precisa ser pelo menos 1.")

    command = [
        executable,
        "--config-path",
        str(config),
        "--syntax",
        "Luau",
        "--num-threads",
        str(thread_count),
    ]
    if args.verify:
        command.append("--verify")

    for flag, value in (
        ("--column-width", args.column_width),
        ("--indent-type", args.indent_type),
        ("--indent-width", args.indent_width),
        ("--quote-style", args.quote_style),
        ("--collapse-simple-statement", args.collapse_simple_statement),
    ):
        if value is not None:
            command.extend((flag, str(value)))

    command.extend(str(path) for path in staged_files)
    return command

def run_stylua(
    command: Sequence[str],
    stage_root: Path,
    staged_to_source: dict[Path, Path],
) -> None:
    file_arguments = [str(path) for path in staged_to_source]
    fixed_arguments = list(command[: -len(file_arguments)])
    argument_limit = 24 * 1024 if platform.system() == "Windows" else 128 * 1024
    if platform.system() != "Windows":
        try:
            argument_limit = min(argument_limit, int(os.sysconf("SC_ARG_MAX")) // 2)
        except (AttributeError, OSError, ValueError):
            pass

    batches: list[list[str]] = []
    current_batch: list[str] = []
    current_size = sum(len(os.fsencode(value)) + 1 for value in fixed_arguments)
    for path in file_arguments:
        path_size = len(os.fsencode(path)) + 1
        if current_batch and current_size + path_size > argument_limit:
            batches.append(current_batch)
            current_batch = []
            current_size = sum(len(os.fsencode(value)) + 1 for value in fixed_arguments)
        current_batch.append(path)
        current_size += path_size
    if current_batch:
        batches.append(current_batch)

    try:
        for batch in batches:
            result = subprocess.run(
                [*fixed_arguments, *batch],
                cwd=stage_root,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            if result.returncode == 0:
                continue

            message = (
                result.stderr.strip()
                or result.stdout.strip()
                or "falha sem mensagem do StyLua"
            )
            for staged, source in staged_to_source.items():
                message = message.replace(str(staged), str(source))
                message = message.replace(staged.name, str(source))
            raise FormatterError(f"StyLua falhou:\n{message}")
    except OSError as error:
        if error.errno == errno.E2BIG:
            raise FormatterError(
                "O lote excedeu o limite de argumentos do sistema; reduza a quantidade de arquivos."
            ) from error
        raise
