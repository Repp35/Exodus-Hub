"""File selection, CLI validation and atomic formatting pipeline."""
from __future__ import annotations
import argparse
import fnmatch
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable, Sequence

from .rules import (
    FormatterError,
    valid_section,
    normalize_section_case,
    strip_unwanted_comments,
    add_section_spacing,
    remove_empty_lines,
    add_initial_dependency_spacing,
    add_table_spacing,
    expand_inline_config_tables,
    expand_dense_named_tables,
    expand_module_declarations,
    add_final_return_spacing,
    add_title,
    require_sections,
    organize_literal_constants,
    apply_directives,
    parse_section_specs,
    parse_section_edits,
    edit_sections,
    insert_sections,
    compact_statement_runs,
    compact_simple_if_blocks,
    LUA_SUFFIXES,
    SKIP_DIRS,
)
from .backend import (
    integer_stylua_setting,
    string_stylua_setting,
    find_stylua,
    make_stylua_command,
    run_stylua,
    HUB_ROOT,
    DEFAULT_CONFIG,
)

def is_excluded(path: Path, root: Path, patterns: Sequence[str]) -> bool:
    relative = path.relative_to(root)
    if any(part in SKIP_DIRS for part in relative.parts[:-1]):
        return True
    if path.stem.endswith("_formatted"):
        return True

    relative_name = relative.as_posix()
    return any(
        fnmatch.fnmatchcase(relative_name, pattern)
        or fnmatch.fnmatchcase(path.name, pattern)
        for pattern in patterns
    )

def walk_directory(root: Path, patterns: Sequence[str]) -> Iterable[Path]:
    for current, directory_names, file_names in os.walk(root):
        directory_names[:] = sorted(
            name for name in directory_names if name not in SKIP_DIRS
        )
        folder = Path(current)
        for file_name in sorted(file_names):
            path = folder / file_name
            if path.suffix.lower() in LUA_SUFFIXES and not is_excluded(
                path, root, patterns
            ):
                yield path

def collect_files(paths: Sequence[Path], patterns: Sequence[str]) -> list[Path]:
    requested = list(paths) or [HUB_ROOT]
    files: dict[Path, Path] = {}

    for requested_path in requested:
        path = requested_path.expanduser()
        if not path.exists():
            raise FormatterError(f"Caminho não encontrado: {path}")

        if path.is_dir():
            root = path.resolve()
            for candidate in walk_directory(root, patterns):
                resolved = candidate.resolve()
                files.setdefault(resolved, resolved)
            continue

        if not path.is_file():
            raise FormatterError(f"Não é um arquivo ou pasta: {path}")
        if path.suffix.lower() not in LUA_SUFFIXES:
            raise FormatterError(f"O arquivo precisa ser .lua ou .luau: {path}")

        resolved = path.resolve()
        files.setdefault(resolved, resolved)

    if not files:
        raise FormatterError("Nenhum arquivo .lua ou .luau encontrado.")
    return sorted(files.values(), key=lambda item: str(item).casefold())

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Formata arquivos Lua/Luau em lote usando o StyLua e as preferências "
            "definidas em stylua.toml. Sem caminhos, processa a pasta do hub."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="arquivos .lua/.luau ou pastas; pastas são percorridas recursivamente",
    )

    output = parser.add_mutually_exclusive_group()
    output.add_argument(
        "--in-place",
        action="store_true",
        help="substitui os arquivos de entrada depois de formatar todo o lote",
    )
    output.add_argument(
        "--check",
        action="store_true",
        help="apenas informa quais arquivos seriam alterados; retorna código 1 se houver",
    )

    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="arquivo de preferências TOML do StyLua",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="PADRAO",
        help="ignora nomes ou caminhos que correspondam ao padrão; pode ser repetido",
    )
    parser.add_argument(
        "--title",
        help="substitui o título; sem título no código, usa o nome do arquivo sem extensão",
    )
    parser.add_argument(
        "--directive",
        action="append",
        choices=("strict", "nonstrict", "nocheck", "native"),
        default=[],
        help="preserva ou adiciona uma diretiva Luau --! no início; pode repetir",
    )
    parser.add_argument(
        "--section",
        action="append",
        default=[],
        metavar="NOME=TRECHO",
        help="insere uma seção antes da primeira linha de código que contenha o trecho; pode repetir",
    )
    parser.add_argument(
        "--section-case-exception",
        action="append",
        default=[],
        metavar="NOME",
        help="preserva a capitalização desta seção em vez de converter para minúsculas; pode repetir",
    )
    parser.add_argument(
        "--edit-section",
        action="append",
        default=[],
        metavar="ATUAL=NOVO",
        help="renomeia uma seção existente sem mudar sua posição; pode repetir",
    )
    parser.add_argument(
        "--remove-section",
        action="append",
        default=[],
        metavar="NOME",
        help="remove uma seção existente; pode repetir",
    )
    parser.add_argument("--column-width", type=int, help="substitui a largura configurada")
    parser.add_argument(
        "--indent-type", choices=("Tabs", "Spaces"), help="substitui o tipo de indentação"
    )
    parser.add_argument("--indent-width", type=int, help="substitui a largura de indentação")
    parser.add_argument(
        "--quote-style",
        choices=("AutoPreferDouble", "AutoPreferSingle", "ForceDouble", "ForceSingle"),
        help="substitui a preferência de aspas",
    )
    parser.add_argument(
        "--collapse-simple-statement",
        choices=("Never", "FunctionOnly", "ConditionalOnly", "Always"),
        help="substitui a preferência de compactação de blocos simples",
    )
    parser.add_argument(
        "--compact-statements", action=argparse.BooleanOptionalAction, default=True,
        help="junta instruções e condicionais simples dentro do limite de largura (padrão: ativado)",
    )
    parser.add_argument(
        "--compact-width",
        type=int,
        default=200,
        help="largura máxima para compactação de instruções e blocos simples (padrão: 200)",
    )
    parser.add_argument(
        "--max-statements",
        type=int,
        default=2,
        help="máximo de instruções simples por linha compactada (padrão: 2)",
    )
    parser.add_argument(
        "--threads",
        type=int,
        help="quantidade de arquivos formatados em paralelo (padrão: até 8)",
    )
    parser.add_argument(
        "--verify",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="pede ao StyLua para conferir se a formatação preservou a AST",
    )
    parser.add_argument("--verbose", action="store_true", help="mostra detalhes da execução")
    return parser

def output_path_for(source: Path, in_place: bool) -> Path:
    if in_place:
        return source
    return source.with_name(f"{source.stem}_formatted{source.suffix}")

def write_atomically(destination: Path, content: str, mode: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, destination)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()

def format_files(args: argparse.Namespace) -> int:
    sources = collect_files(args.paths, args.exclude)
    sections = parse_section_specs(args.section)
    section_case_exceptions = [name.strip() for name in args.section_case_exception]
    if any(not valid_section(name) for name in section_case_exceptions):
        raise FormatterError("--section-case-exception aceita apenas nomes de seção válidos.")
    section_edits = parse_section_edits(args.edit_section)
    section_removals = [name.strip() for name in args.remove_section]
    if any(not valid_section(name) for name in section_removals):
        raise FormatterError("--remove-section aceita apenas um nome de seção válido.")
    if sections and (section_edits or section_removals):
        raise FormatterError("Use --section para criar seções ou --edit-section/--remove-section para editar as existentes.")
    directive_modes = {"strict", "nonstrict", "nocheck"}.intersection(args.directive)
    if len(directive_modes) > 1:
        raise FormatterError("Escolha apenas uma diretiva entre strict, nonstrict e nocheck.")
    if args.title is not None:
        args.title = args.title.strip()
        if not args.title or any(char in args.title for char in "\r\n") or "]]" in args.title:
            raise FormatterError("--title precisa ser um título de uma linha, sem ']]'.")
    if not args.in_place:
        source_set = set(sources)
        for source_path in sources:
            destination = output_path_for(source_path, in_place=False)
            if destination in source_set and destination != source_path:
                raise FormatterError(
                    f"A saída de {source_path} sobrescreveria um arquivo selecionado: {destination}"
                )
    config = args.config.expanduser().resolve()
    if not config.is_file():
        raise FormatterError(f"Configuração do StyLua não encontrada: {config}")
    if args.column_width is not None and args.column_width < 1:
        raise FormatterError("--column-width precisa ser maior que zero.")
    if args.indent_width is not None and args.indent_width < 1:
        raise FormatterError("--indent-width precisa ser maior que zero.")
    if args.compact_width is not None and args.compact_width < 1:
        raise FormatterError("--compact-width precisa ser maior que zero.")
    if args.max_statements < 1:
        raise FormatterError("--max-statements precisa ser maior que zero.")

    executable = find_stylua()
    staged_to_source: dict[Path, Path] = {}

    with tempfile.TemporaryDirectory(prefix="exodus-format-") as temporary_directory:
        stage_root = Path(temporary_directory)
        staged_files = []

        for index, source_path in enumerate(sources, start=1):
            try:
                source = source_path.read_text(encoding="utf-8-sig")
            except UnicodeDecodeError as error:
                raise FormatterError(f"Arquivo não está em UTF-8: {source_path} ({error})") from error

            prepared = source
            prepared = strip_unwanted_comments(prepared, preserve_sections=True)
            prepared = organize_literal_constants(prepared)
            prepared = remove_empty_lines(prepared)
            if section_edits or section_removals:
                prepared = edit_sections(
                    prepared,
                    section_edits,
                    section_removals,
                    source_path,
                )
            if sections:
                prepared = insert_sections(prepared, sections, source_path)
            prepared = normalize_section_case(prepared, section_case_exceptions)
            prepared = add_section_spacing(prepared)
            prepared = add_table_spacing(prepared)
            prepared = add_final_return_spacing(prepared)
            prepared = apply_directives(prepared, args.directive)
            prepared = add_title(prepared, source_path.name, args.title)
            prepared = require_sections(prepared, source_path.name)
            prepared = add_initial_dependency_spacing(prepared)
            staged_path = stage_root / f"{index:05d}_{source_path.name}"
            staged_path.write_text(prepared, encoding="utf-8", newline="\n")
            staged_files.append(staged_path)
            staged_to_source[staged_path] = source_path

        command = make_stylua_command(executable, config, staged_files, args)
        if args.verbose:
            thread_count = command[command.index("--num-threads") + 1]
            print(f"StyLua: {len(sources)} arquivo(s), {thread_count} thread(s)")
        run_stylua(command, stage_root, staged_to_source)

        configured_indent = integer_stylua_setting(config, "indent_width", 4)
        compact_width = args.compact_width
        tab_width = args.indent_width or configured_indent
        configured_indent_type = args.indent_type or string_stylua_setting(config, "indent_type", "Tabs")

        def formatted_content(staged_path: Path, source_path: Path) -> str:
            formatted = staged_path.read_text(encoding="utf-8")
            formatted = strip_unwanted_comments(formatted)
            formatted = remove_empty_lines(formatted)
            formatted = normalize_section_case(formatted, section_case_exceptions)
            formatted = add_section_spacing(formatted)
            formatted = expand_module_declarations(formatted)
            formatted = add_table_spacing(formatted)
            formatted = add_final_return_spacing(formatted)
            formatted = apply_directives(formatted, args.directive)
            formatted = add_title(formatted, source_path.name, args.title)
            formatted = require_sections(formatted, source_path.name)
            formatted = add_initial_dependency_spacing(formatted)
            if args.compact_statements:
                formatted = compact_simple_if_blocks(
                    formatted,
                    max_width=compact_width,
                    max_statements=args.max_statements,
                    tab_width=tab_width,
                    indent_type=configured_indent_type,
                )
                formatted = compact_statement_runs(
                    formatted,
                    max_width=compact_width,
                    max_statements=args.max_statements,
                    tab_width=tab_width,
                )
            formatted = expand_inline_config_tables(formatted, configured_indent_type, tab_width)
            while True:
                expanded = expand_dense_named_tables(formatted, configured_indent_type, tab_width)
                if expanded == formatted:
                    break
                formatted = expanded
            formatted = expand_module_declarations(formatted)
            formatted = add_table_spacing(formatted)
            return formatted

        if args.check:
            changed = []
            for staged_path, source_path in staged_to_source.items():
                formatted = formatted_content(staged_path, source_path)
                try:
                    original = source_path.read_text(encoding="utf-8-sig")
                except UnicodeDecodeError as error:
                    raise FormatterError(
                        f"Arquivo não está em UTF-8: {source_path} ({error})"
                    ) from error
                if formatted != original:
                    changed.append(source_path)
                    print(f"Precisa formatar: {source_path}")
            if not changed:
                print(f"Formatado: {len(sources)} arquivo(s); nenhuma alteração necessária.")
            return 1 if changed else 0

        for staged_path, source_path in staged_to_source.items():
            destination = output_path_for(source_path, args.in_place)
            permissions = source_path.stat().st_mode & 0o777
            write_atomically(
                destination,
                formatted_content(staged_path, source_path),
                permissions,
            )
            if args.verbose:
                print(f"Formatado: {destination}")

    if not args.verbose:
        mode = "no lugar" if args.in_place else "em cópias"
        print(f"Formatados {len(sources)} arquivo(s) {mode}.")
    return 0

def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return format_files(args)
    except (FormatterError, OSError, subprocess.SubprocessError) as error:
        print(f"Erro: {error}", file=sys.stderr)
        return 2
