{$$} = require 'space-pencil'
Keymap = require '../src/keymap'
{keydownEvent, appendContent} = require './spec-helper'

describe "Keymap", ->
  keymap = null

  beforeEach ->
    keymap = new Keymap

  describe "::handleKeyboardEvent(event)", ->
    describe "when the keystroke matches no bindings", ->
      it "does not stop propagation of the event", ->
        event = keydownEvent('q')
        spyOn(event, 'stopPropagation')
        spyOn(event, 'stopImmediatePropagation')
        keymap.handleKeyboardEvent(event)
        expect(event.stopPropagation).not.toHaveBeenCalled()
        expect(event.stopImmediatePropagation).not.toHaveBeenCalled()

    describe "when the keystroke matches one binding on any particular element", ->
      [events, elementA, elementB] = []

      beforeEach ->
        elementA = appendContent $$ ->
          @div class: 'a', ->
            @div class: 'b'
        elementB = elementA.querySelector('.b')

        events = []
        elementA.addEventListener 'x-command', ((e) -> events.push(e)), false
        elementA.addEventListener 'y-command', ((e) -> events.push(e)), false

        keymap.addKeyBindings "test",
          ".a":
            "ctrl-x": "x-command"
            "ctrl-y": "y-command"
          ".b":
            "ctrl-y": "y-command"

      it "dispatches the command event on the first matching ancestor of the target", ->
        keymap.handleKeyboardEvent(keydownEvent('y', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'y-command'
        expect(events[0].target).toBe elementB

        events = []
        keymap.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'x-command'
        expect(events[0].target).toBe elementB

  describe "when the keystroke matches multiple bindings on the same element", ->
    [elementA, elementB, events] = []

    beforeEach ->
      elementA = appendContent $$ ->
        @div class: 'a', ->
          @div class: 'b c d'
      elementB = elementA.querySelector('.b')

      events = []
      elementA.addEventListener 'command-1', ((e) -> events.push(e)), false
      elementA.addEventListener 'command-2', ((e) -> events.push(e)), false

    describe "when the bindings have selectors with different specificity", ->
      beforeEach ->
        keymap.addKeyBindings "test",
          ".b.c":
            "ctrl-x": "command-1"
          ".b":
            "ctrl-x": "command-2"

      it "dispatches the command associated with the most specific binding", ->
        keymap.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'command-1'
        expect(events[0].target).toBe elementB

    describe "when the bindings have selectors with the same specificity", ->
      beforeEach ->
        keymap.addKeyBindings "test",
          ".b.c":
            "ctrl-x": "command-1"
          ".c.d":
            "ctrl-x": "command-2"

      it "dispatches the command associated with the most recently added binding", ->
        keymap.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'command-2'
        expect(events[0].target).toBe elementB

  describe "::addKeyBindings(source, bindings)", ->
    it "normalizes keystrokes containing capitalized alphabetic characters", ->
      keymap.addKeyBindings 'test', '*': 'ctrl-shift-l': 'a'
      keymap.addKeyBindings 'test', '*': 'ctrl-shift-L': 'b'
      keymap.addKeyBindings 'test', '*': 'ctrl-L': 'c'
      expect(keymap.keyBindingsForCommand('a')[0].keystrokeSequence).toBe 'ctrl-shift-L'
      expect(keymap.keyBindingsForCommand('b')[0].keystrokeSequence).toBe 'ctrl-shift-L'
      expect(keymap.keyBindingsForCommand('c')[0].keystrokeSequence).toBe 'ctrl-shift-L'

    it "normalizes the order of modifier keys based on the Apple interface guidelines", ->
      keymap.addKeyBindings 'test', '*': 'alt-cmd-ctrl-shift-l': 'a'
      keymap.addKeyBindings 'test', '*': 'shift-ctrl-l': 'b'
      keymap.addKeyBindings 'test', '*': 'alt-ctrl-l': 'c'
      keymap.addKeyBindings 'test', '*': 'ctrl-alt--': 'd'

      expect(keymap.keyBindingsForCommand('a')[0].keystrokeSequence).toBe 'ctrl-alt-shift-cmd-L'
      expect(keymap.keyBindingsForCommand('b')[0].keystrokeSequence).toBe 'ctrl-shift-L'
      expect(keymap.keyBindingsForCommand('c')[0].keystrokeSequence).toBe 'ctrl-alt-l'
      expect(keymap.keyBindingsForCommand('d')[0].keystrokeSequence).toBe 'ctrl-alt--'

  describe "::keystrokeForKeyboardEvent(event)", ->
    describe "when no modifiers are pressed", ->
      it "returns a string that identifies the unmodified keystroke", ->
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('a'))).toBe 'a'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('['))).toBe '['
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('*'))).toBe '*'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('left'))).toBe 'left'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('\b'))).toBe 'backspace'

    describe "when a modifier key is combined with a non-modifier key", ->
      it "returns a string that identifies the modified keystroke", ->
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('a', alt: true))).toBe 'alt-a'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('[', cmd: true))).toBe 'cmd-['
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('*', ctrl: true))).toBe 'ctrl-*'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('left', ctrl: true, alt: true, cmd: true))).toBe 'ctrl-alt-cmd-left'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('A', shift: true))).toBe 'shift-A'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('{', shift: true))).toBe '{'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('left', shift: true))).toBe 'shift-left'
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('Left', shift: true))).toBe 'shift-left'

    describe "when a non-English keyboard language is used", ->
      it "uses the physical character pressed instead of the character it maps to in the current language", ->
        expect(keymap.keystrokeForKeyboardEvent(keydownEvent('U+03B6', cmd: true, which: 122))).toBe 'cmd-z'
