{normalizeKeystrokes} = require '../src/helpers'

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

    expect(normalizeKeystrokes('a-b')).toBe false
    expect(normalizeKeystrokes('---')).toBe false
    expect(normalizeKeystrokes('cmd-a-b')).toBe false

    expect(-> normalizeKeystrokes('-a-b')).toThrow()
    expect(-> normalizeKeystrokes('ctrl-')).toThrow()
    expect(-> normalizeKeystrokes('--')).toThrow()
    expect(-> normalizeKeystrokes('- ')).toThrow()
    expect(-> normalizeKeystrokes('a ')).toThrow()
