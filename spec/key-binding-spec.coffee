{KeyBinding} = require '../src/key-binding'

describe "KeyBinding", ->
  describe "isMatchedKeydownKeyup", ->

    describe "returns false when the binding...", ->
      it "has no keyups", ->
        kb = keyBindingArgHelper('ctrl-a a 1 2 3')
        assert(not kb.isMatchedKeydownKeyup())
      it "has no keydowns", ->
        kb = keyBindingArgHelper('^ctrl ^a')
        assert(not kb.isMatchedKeydownKeyup())
      it "is a bare modifier keyup", ->
        kb = keyBindingArgHelper('^ctrl')
        assert(not kb.isMatchedKeydownKeyup())
      it "has mismatched last_keystroke: ctrl ^shift", ->
        kb = keyBindingArgHelper('ctrl-a ^shift')
        assert(not kb.isMatchedKeydownKeyup())
      it "has mismatched last_keystroke: cmd ^alt", ->
        kb = keyBindingArgHelper('cmd-a ^alt')
        assert(not kb.isMatchedKeydownKeyup())
      it "has more keyups than keydowns: ctrl ^ctrl-shift", ->
        kb = keyBindingArgHelper('ctrl ^ctrl-shift')
        assert(not kb.isMatchedKeydownKeyup())
      it "has matching keyups that don't come last", ->
        kb = keyBindingArgHelper('ctrl ^ctrl a')
        assert(not kb.isMatchedKeydownKeyup())

    describe "returns true when the binding...", ->
      it "has a matched ctrl", ->
        kb = keyBindingArgHelper('ctrl-a ^ctrl')
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched shift", ->
        kb = keyBindingArgHelper('shift-a ^shift')
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched alt", ->
        kb = keyBindingArgHelper('alt-a ^alt')
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched cmd", ->
        kb = keyBindingArgHelper('cmd-a ^cmd')
        assert(kb.isMatchedKeydownKeyup())
      it "has a matched ctrl-shift", ->
        kb = keyBindingArgHelper('ctrl-shift-a ^ctrl-shift')
        assert(kb.isMatchedKeydownKeyup())
      it "has matched bare last_keystroke", ->
        kb = keyBindingArgHelper('ctrl ^ctrl')
        assert(kb.isMatchedKeydownKeyup())
      it "has partially matching last_keystroke: ctrl-cmd ^ctrl", ->
        kb = keyBindingArgHelper('ctrl-cmd-a ^ctrl')
        assert(kb.isMatchedKeydownKeyup())
      it "has partially matching last_keystroke: ctrl-cmd ^cmd", ->
        kb = keyBindingArgHelper('ctrl-cmd-a ^cmd')
        assert(kb.isMatchedKeydownKeyup())
      it "has partially matching last_keystroke: ctrl-shift ^ctrl", ->
        kb = keyBindingArgHelper('ctrl-shift-a ^ctrl')
        assert(kb.isMatchedKeydownKeyup())
      it "has matching non-modifer", ->
        kb = keyBindingArgHelper('a ^a')
        assert(kb.isMatchedKeydownKeyup())
      it "has matching non-modifer with several intermediate keys", ->
        kb = keyBindingArgHelper('a 1 2 3 ^a')
        assert(kb.isMatchedKeydownKeyup())

  describe ".matchesKeystrokes(userKeystrokes)", ->
    it "returns 'exact' for exact matches", ->
      assert.equal(keyBindingArgHelper('ctrl-tab ^tab ^ctrl').matchesKeystrokes(['ctrl-tab', '^tab', '^ctrl']), 'exact')
      assert.equal(keyBindingArgHelper('ctrl-tab ^ctrl').matchesKeystrokes(['ctrl-tab', '^tab', '^ctrl']), 'exact')
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a', '^a', 'b', '^b', 'c']), 'exact')
      assert.equal(keyBindingArgHelper('a b ^b c').matchesKeystrokes(['a', '^a', 'b', '^b', 'c']), 'exact')

    it "returns false for non-matches", ->
      assert.equal(keyBindingArgHelper('ctrl-tab ^tab').matchesKeystrokes(['ctrl-tab', '^tab', '^ctrl']), false)
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a', '^a', 'b', '^b', 'c', '^c']), false)
      assert.equal(keyBindingArgHelper('a b ^b c').matchesKeystrokes(['a', '^a', 'b', '^b', 'c', '^c']), false)

      assert.equal(keyBindingArgHelper('a').matchesKeystrokes(['a', '^a', 'b', '^b', 'c', '^c']), false)
      assert.equal(keyBindingArgHelper('a').matchesKeystrokes(['a', '^a']), false)
      assert.equal(keyBindingArgHelper('a c').matchesKeystrokes(['a', '^a', 'b', '^b', 'c', '^c']), false)
      assert.equal(keyBindingArgHelper('a b ^d').matchesKeystrokes(['a', '^a', 'b', '^b', 'c', '^c']), false)
      assert.equal(keyBindingArgHelper('a d ^d').matchesKeystrokes(['a', '^a', 'b', '^b', 'c', '^c']), false)
      assert.equal(keyBindingArgHelper('a d ^d').matchesKeystrokes(['^c']), false)

    it "returns 'partial' for partial matches", ->
      assert.equal(keyBindingArgHelper('a b ^b').matchesKeystrokes(['a']), 'partial')
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a']), 'partial')
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a', '^a']), 'partial')
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a', '^a', 'b']), 'partial')
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a', '^a', 'b', '^b']), 'partial')
      assert.equal(keyBindingArgHelper('a b c').matchesKeystrokes(['a', '^a', 'd', '^d']), false)

    it "returns 'keydownExact' for bindings that match and contain a remainder of only keyup events", ->
      assert.equal(keyBindingArgHelper('a b ^b').matchesKeystrokes(['a', 'b']), 'keydownExact')

keyBindingArgHelper = (binding) ->
  return new KeyBinding('test', 'test', binding, 'body', 0)
