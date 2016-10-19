KeyBinding = require '../src/key-binding'

describe "KeyBinding", ->
  describe "isMatchedKeydownKeyup", ->

    describe "returns false when the binding...", ->
      it "has no keyups", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-a a 1 2 3', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())
      it "has no keydowns", ->
        kb = new KeyBinding('test', 'whatever', '^ctrl ^a', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())
      it "is a bare modifier keyup", ->
        kb = new KeyBinding('test', 'whatever', '^ctrl', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())
      it "has mismatched last_keystroke: ctrl ^shift", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-a ^shift', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())
      it "has mismatched last_keystroke: cmd ^alt", ->
        kb = new KeyBinding('test', 'whatever', 'cmd-a ^alt', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())
      it "has more keyups than keydowns: ctrl ^ctrl-shift", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl ^ctrl-shift', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())
      it "has matching keyups that don't come last", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl ^ctrl a', 'body', 0)
        assert(not kb.isMatchedKeydownKeyup())

    describe "returns true when the binding...", ->
      it "has a matched ctrl", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-a ^ctrl', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched shift", ->
        kb = new KeyBinding('test', 'whatever', 'shift-a ^shift', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched alt", ->
        kb = new KeyBinding('test', 'whatever', 'alt-a ^alt', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched cmd", ->
        kb = new KeyBinding('test', 'whatever', 'cmd-a ^cmd', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched ctrl-shift", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-shift-a ^ctrl-shift', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has matched bare last_keystroke", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl ^ctrl', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has partially matching last_keystroke: ctrl-cmd ^ctrl", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-cmd-a ^ctrl', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has partially matching last_keystroke: ctrl-cmd ^cmd", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-cmd-a ^cmd', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has partially matching last_keystroke: ctrl-shift ^ctrl", ->
        kb = new KeyBinding('test', 'whatever', 'ctrl-shift-a ^ctrl', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has matching non-modifer", ->
        kb = new KeyBinding('test', 'whatever', 'a ^a', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
      it "has matching non-modifer with several intermediate keys", ->
        kb = new KeyBinding('test', 'whatever', 'a 1 2 3 ^a', 'body', 0)
        assert(kb.isMatchedKeydownKeyup())
