KeyBinding = require '../src/key-binding'

describe "KeyBinding", ->

  describe "is_matched_modifer_keydown_keyup", ->

    describe "returns false when the binding...", ->
      it "has no modifier keys", ->
        kb = new KeyBinding('test', 'whatever', 'a', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "has no keyups", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-a', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "is a bare modifier", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "is a bare modifier keyup", ->
        kb = new KeyBinding('test', 'whatever', '^ctrl', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "has mismatched last_keystroke: ctrl ^shift", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-a ^shift', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "has mismatched last_keystroke: cmd ^alt", ->
        kb = new KeyBinding('test', 'whatever', 'cmd-a ^alt', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "has partially mismatched last_keystroke: ctrl-cmd ^ctrl", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-cmd-a ^ctrl', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "has partially mismatched last_keystroke: ctrl-cmd ^cmd", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-cmd-a ^cmd', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())
      it "has partially mismatched last_keystroke: ctrl ^ctrl-shift", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl ^ctrl-shift', 'body', 0)
        assert(not kb.is_matched_modifer_keydown_keyup())

    describe "returns true when the binding...", ->
      it "has a matched ctrl", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-a ^ctrl', 'body', 0)
        assert(kb.is_matched_modifer_keydown_keyup())
      it "has a matched shift", ->
        kb = new KeyBinding('test', 'whatever', 'shift-a ^shift', 'body', 0)
        assert(kb.is_matched_modifer_keydown_keyup())
      it "has a matched alt", ->
        kb = new KeyBinding('test', 'whatever', 'alt-a ^alt', 'body', 0)
        assert(kb.is_matched_modifer_keydown_keyup())
      it "has a matched cmd", ->
        kb = new KeyBinding('test', 'whatever', 'cmd-a ^cmd', 'body', 0)
        assert(kb.is_matched_modifer_keydown_keyup())
      it "has a matched ctrl-shift", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-shift-a ^ctrl-shift', 'body', 0)
        assert(kb.is_matched_modifer_keydown_keyup())
      it "has matched bare last_keystroke", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl ^ctrl', 'body', 0)
        assert(kb.is_matched_modifer_keydown_keyup())
