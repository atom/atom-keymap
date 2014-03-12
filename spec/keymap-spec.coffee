Keymap = require '../src/keymap'
{keydownEvent} = require './spec-helper'

describe "Keymap", ->
  keymap = null

  beforeEach ->
    keymap = new Keymap

  describe "::addKeyBindings(source, bindings)", ->
    it "normalizes keystrokes containing capitalized alphabetic characters", ->
      keymap.addKeyBindings 'test', '*': 'ctrl-shift-l': 'a'
      keymap.addKeyBindings 'test', '*': 'ctrl-shift-L': 'b'
      keymap.addKeyBindings 'test', '*': 'ctrl-L': 'c'
      expect(keymap.keyBindingsForCommand('a')[0].keystroke).toBe 'ctrl-shift-L'
      expect(keymap.keyBindingsForCommand('b')[0].keystroke).toBe 'ctrl-shift-L'
      expect(keymap.keyBindingsForCommand('c')[0].keystroke).toBe 'ctrl-shift-L'

    it "normalizes the order of modifier keys based on the Apple interface guidelines", ->
      keymap.addKeyBindings 'test', '*': 'alt-cmd-ctrl-shift-l': 'a'
      keymap.addKeyBindings 'test', '*': 'shift-ctrl-l': 'b'
      keymap.addKeyBindings 'test', '*': 'alt-ctrl-l': 'c'
      keymap.addKeyBindings 'test', '*': 'ctrl-alt--': 'd'

      expect(keymap.keyBindingsForCommand('a')[0].keystroke).toBe 'ctrl-alt-shift-cmd-L'
      expect(keymap.keyBindingsForCommand('b')[0].keystroke).toBe 'ctrl-shift-L'
      expect(keymap.keyBindingsForCommand('c')[0].keystroke).toBe 'ctrl-alt-l'
      expect(keymap.keyBindingsForCommand('d')[0].keystroke).toBe 'ctrl-alt--'

  describe "::keystrokeStringForKeyboardEvent(event)", ->
    describe "when no modifiers are pressed", ->
      it "returns a string that identifies the unmodified keystroke", ->
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('a'))).toBe 'a'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('['))).toBe '['
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('*'))).toBe '*'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('left'))).toBe 'left'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('\b'))).toBe 'backspace'

    describe "when a modifier key is combined with a non-modifier key", ->
      it "returns a string that identifies the modified keystroke", ->
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('a', alt: true))).toBe 'alt-a'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('[', cmd: true))).toBe 'cmd-['
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('*', ctrl: true))).toBe 'ctrl-*'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('left', ctrl: true, alt: true, cmd: true))).toBe 'ctrl-alt-cmd-left'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('A', shift: true))).toBe 'shift-A'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('{', shift: true))).toBe '{'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('left', shift: true))).toBe 'shift-left'
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('Left', shift: true))).toBe 'shift-left'

    describe "when a non-English keyboard language is used", ->
      it "uses the physical character pressed instead of the character it maps to in the current language", ->
        expect(keymap.keystrokeStringForKeyboardEvent(keydownEvent('U+03B6', cmd: true, which: 122))).toBe 'cmd-z'
