{normalizeKeystrokes, keystrokesMatch, isModifierKeyup} = require '../src/helpers'

describe ".normalizeKeystrokes(keystrokes)", ->
  it "parses and normalizes the keystrokes", ->
    assert.equal(normalizeKeystrokes('ctrl--'), 'ctrl--')
    assert.equal(normalizeKeystrokes('ctrl-x'), 'ctrl-x')
    assert.equal(normalizeKeystrokes('a'), 'a')
    assert.equal(normalizeKeystrokes('shift-a'), 'shift-A')
    assert.equal(normalizeKeystrokes('shift-9'), 'shift-9')
    assert.equal(normalizeKeystrokes('-'), '-')
    assert.equal(normalizeKeystrokes('- -'), '- -')
    assert.equal(normalizeKeystrokes('a b'), 'a b')
    assert.equal(normalizeKeystrokes('cmd-k cmd-v'), 'cmd-k cmd-v')
    assert.equal(normalizeKeystrokes('cmd-cmd'), 'cmd')
    assert.equal(normalizeKeystrokes('cmd-shift'), 'shift-cmd')
    assert.equal(normalizeKeystrokes('cmd-shift-a'), 'shift-cmd-A')
    assert.equal(normalizeKeystrokes('cmd-ctrl-alt--'), 'ctrl-alt-cmd--')

    assert.equal(normalizeKeystrokes('ctrl-y   ^y'), 'ctrl-y ^y')
    assert.equal(normalizeKeystrokes('ctrl-y ^ctrl-y'), 'ctrl-y ^y')
    assert.equal(normalizeKeystrokes('cmd-shift-y ^cmd-shift-y'), 'shift-cmd-Y ^y')
    assert.equal(normalizeKeystrokes('ctrl-y ^ctrl-y ^ctrl'), 'ctrl-y ^y ^ctrl')
    assert.equal(normalizeKeystrokes('ctrl-y ^ctrl-shift-alt-cmd-y ^ctrl ^shift ^alt ^cmd'), 'ctrl-y ^y ^ctrl ^shift ^alt ^cmd')
    assert.equal(normalizeKeystrokes('a b c ^a ^b ^c'), 'a b c ^a ^b ^c')

    assert.equal(normalizeKeystrokes('a-b'), false)
    assert.equal(normalizeKeystrokes('---'), false)
    assert.equal(normalizeKeystrokes('cmd-a-b'), false)
    assert.equal(normalizeKeystrokes('-a-b'), false)
    assert.equal(normalizeKeystrokes('ctrl-'), false)
    assert.equal(normalizeKeystrokes('--'), false)
    assert.equal(normalizeKeystrokes('- '), false)
    assert.equal(normalizeKeystrokes('a '), false)

describe ".keystrokesMatch(bindingKeystrokes, userKeystrokes)", ->
  it "returns 'exact' for exact matches", ->
    assert.equal(keystrokesMatch(['ctrl-tab', '^tab', '^ctrl'], ['ctrl-tab', '^tab', '^ctrl']), 'exact')
    assert.equal(keystrokesMatch(['ctrl-tab', '^ctrl'], ['ctrl-tab', '^tab', '^ctrl']), 'exact')
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b', '^b', 'c']), 'exact')
    assert.equal(keystrokesMatch(['a', 'b', '^b', 'c'], ['a', '^a', 'b', '^b', 'c']), 'exact')

  it "returns false for non-matches", ->
    assert.equal(keystrokesMatch(['ctrl-tab', '^tab'], ['ctrl-tab', '^tab', '^ctrl']), false)
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b', '^b', 'c', '^c']), false)
    assert.equal(keystrokesMatch(['a', 'b', '^b', 'c'], ['a', '^a', 'b', '^b', 'c', '^c']), false)

    assert.equal(keystrokesMatch(['a'], ['a', '^a', 'b', '^b', 'c', '^c']), false)
    assert.equal(keystrokesMatch(['a'], ['a', '^a']), false)
    assert.equal(keystrokesMatch(['a', 'c'], ['a', '^a', 'b', '^b', 'c', '^c']), false)
    assert.equal(keystrokesMatch(['a', 'b', '^d'], ['a', '^a', 'b', '^b', 'c', '^c']), false)
    assert.equal(keystrokesMatch(['a', 'd', '^d'], ['a', '^a', 'b', '^b', 'c', '^c']), false)
    assert.equal(keystrokesMatch(['a', 'd', '^d'], ['^c']), false)

  it "returns 'partial' for partial matches", ->
    assert.equal(keystrokesMatch(['a', 'b', '^b'], ['a']), 'partial')
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a']), 'partial')
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a', '^a']), 'partial')
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b']), 'partial')
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b', '^b']), 'partial')
    assert.equal(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'd', '^d']), false)

  it "returns 'keydownExact' for bindings that match and contain a remainder of only keyup events", ->
    assert.equal(keystrokesMatch(['a', 'b', '^b'], ['a', 'b']), 'keydownExact')

describe ".isModifierKeyup(keystroke)", ->
  it "returns true for single modifier keyups", ->
    assert(isModifierKeyup('^ctrl'))
    assert(isModifierKeyup('^shift'))
    assert(isModifierKeyup('^alt'))
    assert(isModifierKeyup('^cmd'))
    assert(isModifierKeyup('^ctrl-shift'))
    assert(isModifierKeyup('^alt-cmd'))

  it "returns false for modifier keydowns", ->
    assert(!isModifierKeyup('ctrl-x'))
    assert(!isModifierKeyup('shift-x'))
    assert(!isModifierKeyup('alt-x'))
    assert(!isModifierKeyup('cmd-x'))
    assert(!isModifierKeyup('ctrl-shift-x'))
    assert(!isModifierKeyup('alt-cmd-x'))
