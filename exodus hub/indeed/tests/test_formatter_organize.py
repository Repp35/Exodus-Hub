import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import formatter


class FormatterOrganizeTests(unittest.TestCase):
    def test_constants_are_grouped_without_changing_local_names(self):
        source = 'local SPEED = 40\nlocal DELAY = 0.5\nreturn SPEED + DELAY\n'
        result = formatter.organize_literal_constants(source)
        self.assertIn('SPEED = 40,', result)
        self.assertIn('local SPEED = CONFIG.SPEED', result)
        self.assertIn('local DELAY = CONFIG.DELAY', result)
        self.assertIn('return SPEED + DELAY', result)
        self.assertEqual(result, formatter.organize_literal_constants(result))

    def test_leaves_existing_config_and_long_strings_alone(self):
        source = 'local CONFIG = {}\nlocal SPEED = 40\n'
        self.assertEqual(source, formatter.organize_literal_constants(source))
        source = 'local text = [[\nlocal SPEED = 40\n]]\nreturn text\n'
        self.assertEqual(source, formatter.organize_literal_constants(source))

    def test_plain_file_is_formatted_and_stable(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'sample.luau'
            path.write_text('local SPEED = 40\nreturn SPEED\n', encoding='utf-8')
            args = formatter.build_parser().parse_args(['--in-place', str(path)])
            self.assertEqual(formatter.format_files(args), 0)
            result = path.read_text(encoding='utf-8')
            self.assertIn('local CONFIG =', result)
            self.assertEqual(formatter.format_files(args), 0)
            self.assertEqual(result, path.read_text(encoding='utf-8'))

    def test_module_declarations_keep_multi_return_assignments_intact(self):
        source = 'local a, b\nlocal x, y = 0, 1\nlocal c, d = getPair()\nlocal text = [[\nlocal fake, names\n]]\n'
        result = formatter.expand_module_declarations(source)
        self.assertIn('local a\nlocal b\n', result)
        self.assertIn('local x = 0\nlocal y = 1\n', result)
        self.assertIn('local c, d = getPair()', result)
        self.assertIn('local fake, names', result)

    def test_nested_config_and_header_stay_expanded_after_second_format(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'organized.luau'
            path.write_text('-- dependencies\nlocal utils, info\n-- configuration\nlocal CONFIG = { A = { X = 1, Y = { Z = 2, W = 3 } }, B = { X = 1, Y = 2 } }\nreturn CONFIG\n')
            args = formatter.build_parser().parse_args(['--in-place', str(path)])
            self.assertEqual(formatter.format_files(args), 0)
            result = path.read_text()
            self.assertIn('local utils\nlocal info', result)
            self.assertNotIn('A = { X', result)
            self.assertNotIn('Y = { Z', result)
            self.assertEqual(formatter.format_files(args), 0)
            self.assertEqual(result, path.read_text())


if __name__ == '__main__':
    unittest.main()
