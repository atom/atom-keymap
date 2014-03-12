Keymap = require '../src/keymap'
{keydownEvent} = require './spec-helper'

describe "Keymap", ->
  keymap = null

  beforeEach ->
    keymap = new Keymap

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
