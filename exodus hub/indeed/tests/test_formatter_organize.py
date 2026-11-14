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


if __name__ == '__main__':
    unittest.main()
