{normalizeKeystrokes, keystrokesMatch} = require '../src/helpers'

describe ".normalizeKeystrokes(keystrokes)", ->
  it "parses and normalizes the keystrokes", ->
    expect(normalizeKeystrokes('ctrl--')).toBe 'ctrl--'
    expect(normalizeKeystrokes('ctrl-x')).toBe 'ctrl-x'
    expect(normalizeKeystrokes('a')).toBe 'a'
    expect(normalizeKeystrokes('shift-a')).toBe 'shift-A'
    expect(normalizeKeystrokes('shift-9')).toBe 'shift-9'
    expect(normalizeKeystrokes('-')).toBe '-'
    expect(normalizeKeystrokes('- -')).toBe '- -'
    expect(normalizeKeystrokes('a b')).toBe 'a b'
    expect(normalizeKeystrokes('cmd-k cmd-v')).toBe 'cmd-k cmd-v'
    expect(normalizeKeystrokes('cmd-cmd')).toBe 'cmd'
    expect(normalizeKeystrokes('cmd-shift')).toBe 'shift-cmd'
    expect(normalizeKeystrokes('cmd-shift-a')).toBe 'shift-cmd-A'
    expect(normalizeKeystrokes('cmd-ctrl-alt--')).toBe 'ctrl-alt-cmd--'

    expect(normalizeKeystrokes('ctrl-y   ^y')).toBe 'ctrl-y ^y'
    expect(normalizeKeystrokes('ctrl-y ^ctrl-y')).toBe 'ctrl-y ^y'
    expect(normalizeKeystrokes('cmd-shift-y ^cmd-shift-y')).toBe 'shift-cmd-Y ^y'
    expect(normalizeKeystrokes('ctrl-y ^ctrl-y ^ctrl')).toBe 'ctrl-y ^y ^ctrl'
    expect(normalizeKeystrokes('ctrl-y ^ctrl-shift-alt-cmd-y ^ctrl ^shift ^alt ^cmd')).toBe 'ctrl-y ^y ^ctrl ^shift ^alt ^cmd'
    expect(normalizeKeystrokes('a b c ^a ^b ^c')).toBe 'a b c ^a ^b ^c'

    expect(normalizeKeystrokes('a-b')).toBe false
    expect(normalizeKeystrokes('---')).toBe false
    expect(normalizeKeystrokes('cmd-a-b')).toBe false
    expect(normalizeKeystrokes('-a-b')).toBe false
    expect(normalizeKeystrokes('ctrl-')).toBe false
    expect(normalizeKeystrokes('--')).toBe false
    expect(normalizeKeystrokes('- ')).toBe false
    expect(normalizeKeystrokes('a ')).toBe false

describe ".keystrokesMatch(bindingKeystrokes, userKeystrokes)", ->
  it "returns 'exact' for exact matches", ->
    expect(keystrokesMatch(['ctrl-tab', '^tab', '^ctrl'], ['ctrl-tab', '^tab', '^ctrl'])).toBe 'exact'
    expect(keystrokesMatch(['ctrl-tab', '^ctrl'], ['ctrl-tab', '^tab', '^ctrl'])).toBe 'exact'
    expect(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b', '^b', 'c'])).toBe 'exact'
    expect(keystrokesMatch(['a', 'b', '^b', 'c'], ['a', '^a', 'b', '^b', 'c'])).toBe 'exact'

  it "returns false for non-matches", ->
    expect(keystrokesMatch(['ctrl-tab', '^tab'], ['ctrl-tab', '^tab', '^ctrl'])).toBe false
    expect(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b', '^b', 'c', '^c'])).toBe false
    expect(keystrokesMatch(['a', 'b', '^b', 'c'], ['a', '^a', 'b', '^b', 'c', '^c'])).toBe false

    expect(keystrokesMatch(['a'], ['a', '^a', 'b', '^b', 'c', '^c'])).toBe false
    expect(keystrokesMatch(['a'], ['a', '^a'])).toBe false
    expect(keystrokesMatch(['a', 'c'], ['a', '^a', 'b', '^b', 'c', '^c'])).toBe false
    expect(keystrokesMatch(['a', 'b', '^d'], ['a', '^a', 'b', '^b', 'c', '^c'])).toBe false
    expect(keystrokesMatch(['a', 'd', '^d'], ['a', '^a', 'b', '^b', 'c', '^c'])).toBe false
    expect(keystrokesMatch(['a', 'd', '^d'], ['^c'])).toBe false

  it "returns 'partial' for partial matches", ->
    expect(keystrokesMatch(['a', 'b', '^b'], ['a'])).toBe 'partial'
    expect(keystrokesMatch(['a', 'b', 'c'], ['a'])).toBe 'partial'
    expect(keystrokesMatch(['a', 'b', 'c'], ['a', '^a'])).toBe 'partial'
    expect(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b'])).toBe 'partial'
    expect(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'b', '^b'])).toBe 'partial'
    expect(keystrokesMatch(['a', 'b', 'c'], ['a', '^a', 'd', '^d'])).toBe false

  it "returns 'keydownExact' for bindings that match and contain a remainder of only keyup events", ->
    expect(keystrokesMatch(['a', 'b', '^b'], ['a', 'b'])).toBe 'keydownExact'
