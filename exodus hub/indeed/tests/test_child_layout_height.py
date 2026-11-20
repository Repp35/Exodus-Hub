"""Disclosure height is local to its visible controls, independent of window scale."""
import unittest
import test_ui_library as ui_tests

class ChildLayoutHeight(unittest.TestCase):
    def test_nested_children_do_not_multiply_height_by_window_scale(self):
        ui_tests.UILibraryTests().run_lua('''
local scale=Instance.new('UIScale');scale.Scale=.5;scale.Parent=screen
local values={Parent=true,Child=true}
local kit=newKit({reducedMotion=true})
local definitions={{id='main',title='Main',columns=1,sections={{components={
 {kind='toggle',key='Parent'},
 {kind='toggle',key='Child',parentKey='Parent'},
 {kind='toggle',key='Grandchild',parentKey='Child'},
}}}}}
local pages=uipages.create(kit,panel,definitions,{desktop=true,read=function(k) return values[k] end})
pages.refresh();pages.refresh();finishTweens()
local child=pages.getControl('Child');local grandchild=pages.getControl('Grandchild')
local content=grandchild.Root.Parent.Parent
local container=content.Parent
assert(container.Size.Y.Offset==grandchild.Root.Size.Y.Offset,'scale inflated the grandchild container')
scale.Scale=.25;pages.refresh();finishTweens()
assert(container.Size.Y.Offset==grandchild.Root.Size.Y.Offset,'rescaling inflated the container')
values.Child=false;pages.refresh();finishTweens()
assert(container.Size.Y.Offset==0 and not container.Visible,'collapsed child left empty space')
kit.destroy()
''')
