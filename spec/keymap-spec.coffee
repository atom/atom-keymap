path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
{$$} = require 'space-pencil'
{keydownEvent, appendContent} = require './spec-helper'
Keymap = require '../src/keymap'

describe "Keymap", ->
  keymap = null

  beforeEach ->
    keymap = new Keymap

  afterEach ->
    keymap.destroy()

  describe "::handleKeyboardEvent(event)", ->
    describe "when the keystroke matches no bindings", ->
      it "does not prevent the event's default action", ->
        event = keydownEvent('q')
        keymap.handleKeyboardEvent(event)
        expect(event.defaultPrevented).toBe false

    describe "when the keystroke matches one binding on any particular element", ->
      [events, elementA, elementB] = []

      beforeEach ->
        elementA = appendContent $$ ->
          @div class: 'a', ->
            @div class: 'b c'
        elementB = elementA.firstChild

        events = []
        elementA.addEventListener 'x-command', (e) -> events.push(e)
        elementA.addEventListener 'y-command', (e) -> events.push(e)

        keymap.addKeyBindings "test",
          ".a":
            "ctrl-x": "x-command"
            "ctrl-y": "y-command"
          ".c":
            "ctrl-y": "z-command"
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
        expect(events[0].target).toBe elementA

      it "prevents the default action", ->
        event = keydownEvent('y', ctrl: true, target: elementB)
        keymap.handleKeyboardEvent(event)
        expect(event.defaultPrevented).toBe true

      describe "if .abortKeyBinding() is called on the command event", ->
        it "proceeds directly to the next matching binding", ->
          elementB.addEventListener 'y-command', (e) -> events.push(e); e.abortKeyBinding()
          elementB.addEventListener 'y-command', (e) -> events.push(e) # should never be called
          elementB.addEventListener 'z-command', (e) -> events.push(e); e.abortKeyBinding()

          keymap.handleKeyboardEvent(keydownEvent('y', ctrl: true, target: elementB))

          expect(events.length).toBe 3
          expect(events[0].type).toBe 'y-command'
          expect(events[0].target).toBe elementB
          expect(events[1].type).toBe 'z-command'
          expect(events[1].target).toBe elementB
          expect(events[2].type).toBe 'y-command'
          expect(events[2].target).toBe elementA

      describe "if the keyboard event's target is document.body", ->
        it "starts matching keybindings at the .defaultTarget", ->
          keymap.defaultTarget = elementA
          keymap.handleKeyboardEvent(keydownEvent('y', ctrl: true, target: document.body))
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'y-command'
          expect(events[0].target).toBe elementA

      describe "if matching binding's command is 'native!'", ->
        it "terminates without preventing the browser's default action", ->
          keymap.addKeyBindings "test",
            ".b":
              "ctrl-y": "native!"
          elementA.addEventListener 'native!', (e) -> events.push(e)

          event = keydownEvent('y', ctrl: true, target: elementB)
          keymap.handleKeyboardEvent(event)
          expect(events).toEqual []
          expect(event.defaultPrevented).toBe false

    describe "when the keystroke matches multiple bindings on the same element", ->
      [elementA, elementB, events] = []

      beforeEach ->
        elementA = appendContent $$ ->
          @div class: 'a', ->
            @div class: 'b c d'
        elementB = elementA.firstChild

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

    describe "when the keystroke partially matches bindings", ->
      [workspace, editor, events] = []

      beforeEach ->
        workspace = appendContent $$ ->
          @div class: 'workspace', ->
            @div class: 'editor'
        editor = workspace.firstChild

        keymap.addKeyBindings 'test',
          '.workspace': 'v i v a': 'viva!'
          '.editor': 'v': 'enter-visual-mode'
          '.editor.visual-mode': 'i w': 'select-inside-word'

        events = []
        workspace.addEventListener 'viva!', -> events.push('viva!')
        workspace.addEventListener 'select-inside-word', -> events.push('select-inside-word')
        workspace.addEventListener 'enter-visual-mode', -> events.push('enter-visual-mode'); editor.classList.add('visual-mode')

      describe "when subsequent keystrokes yield an exact match", ->
        it "dispatches the command associated with the matched multi-keystroke binding", ->
          keymap.handleKeyboardEvent(keydownEvent('v', target: editor))
          keymap.handleKeyboardEvent(keydownEvent('i', target: editor))
          keymap.handleKeyboardEvent(keydownEvent('v', target: editor))
          keymap.handleKeyboardEvent(keydownEvent('a', target: editor))
          expect(events).toEqual ['viva!']

      describe "when subsequent keystrokes yield no matches", ->
        it "disables the bindings with the longest keystroke sequences and replays the queued keystrokes", ->
          keymap.handleKeyboardEvent(vEvent = keydownEvent('v', target: editor))
          keymap.handleKeyboardEvent(iEvent = keydownEvent('i', target: editor))
          keymap.handleKeyboardEvent(wEvent = keydownEvent('w', target: editor))
          expect(vEvent.defaultPrevented).toBe true
          expect(iEvent.defaultPrevented).toBe true
          expect(wEvent.defaultPrevented).toBe true
          expect(events).toEqual ['enter-visual-mode', 'select-inside-word']

          events = []
          keymap.handleKeyboardEvent(vEvent = keydownEvent('v', target: editor))
          keymap.handleKeyboardEvent(iEvent = keydownEvent('i', target: editor))
          keymap.handleKeyboardEvent(kEvent = keydownEvent('k', target: editor))
          expect(vEvent.defaultPrevented).toBe true
          expect(iEvent.defaultPrevented).toBe true
          expect(kEvent.defaultPrevented).toBe false
          expect(events).toEqual ['enter-visual-mode']
          expect(clearTimeout).toHaveBeenCalled()

      describe "when there are no subsequent keystrokes for ::partialMatchTimeout", ->
        it "disables the bindings with the longest keystroke sequences and replays the queued keystrokes", ->
          keymap.handleKeyboardEvent(keydownEvent('v', target: editor))
          expect(events).toEqual []
          advanceClock(keymap.partialMatchTimeout)
          expect(events).toEqual ['enter-visual-mode']

    it "only counts entire keystrokes when checking for partial matches", ->
      element = $$ -> @div class: 'a'
      keymap.addKeyBindings 'test',
        '.a':
          'ctrl-alt-a': 'command-a'
          'ctrl-a': 'command-b'
      events = []
      element.addEventListener 'command-a', -> events.push('command-a')
      element.addEventListener 'command-b', -> events.push('command-b')

      # Should *only* match ctrl-a, not ctrl-alt-a (can't just use a textual prefix match)
      keymap.handleKeyboardEvent(keydownEvent('a', ctrl: true, target: element))
      expect(events).toEqual ['command-b']

    it "does not enqueue keydown events consisting only of modifier keys", ->
      element = $$ -> @div class: 'a'
      keymap.addKeyBindings 'test', '.a': 'ctrl-a ctrl-b': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      # Simulate keydown events for the modifier key being pressed on its own
      # prior to the key it is modifying.
      keymap.handleKeyboardEvent(keydownEvent('ctrl', target: element))
      keymap.handleKeyboardEvent(keydownEvent('a', ctrl: true, target: element))
      keymap.handleKeyboardEvent(keydownEvent('ctrl', target: element))
      keymap.handleKeyboardEvent(keydownEvent('b', ctrl: true, target: element))

      expect(events).toEqual ['command']

    it "allows solo modifier-keys to be bound", ->
      element = $$ -> @div class: 'a'
      keymap.addKeyBindings 'test', '.a': 'ctrl': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      keymap.handleKeyboardEvent(keydownEvent('ctrl', target: element))
      expect(events).toEqual ['command']

    it "simulates bubbling if the target is detached", ->
      elementA = $$ ->
        @div class: 'a', ->
          @div class: 'b', ->
            @div class: 'c'
      elementB = elementA.firstChild
      elementC = elementB.firstChild

      keymap.addKeyBindings 'test', '.c': 'x': 'command'

      events = []
      elementA.addEventListener 'command', -> events.push('a')
      elementB.addEventListener 'command', (e) ->
        events.push('b1')
        e.stopImmediatePropagation()
      elementB.addEventListener 'command', (e) ->
        events.push('b2')
        expect(e.target).toBe elementC
        expect(e.currentTarget).toBe elementB
      elementC.addEventListener 'command', (e) ->
        events.push('c')
        expect(e.target).toBe elementC
        expect(e.currentTarget).toBe elementC

      keymap.handleKeyboardEvent(keydownEvent('x', target: elementC))

      expect(events).toEqual ['c', 'b1']

  describe "::addKeyBindings(source, bindings)", ->
    it "normalizes keystrokes containing capitalized alphabetic characters", ->
      keymap.addKeyBindings 'test', '*': 'ctrl-shift-l': 'a'
      keymap.addKeyBindings 'test', '*': 'ctrl-shift-L': 'b'
      keymap.addKeyBindings 'test', '*': 'ctrl-L': 'c'
      expect(keymap.findKeyBindings(command: 'a')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymap.findKeyBindings(command: 'b')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymap.findKeyBindings(command: 'c')[0].keystrokes).toBe 'ctrl-shift-L'

    it "normalizes the order of modifier keys based on the Apple interface guidelines", ->
      keymap.addKeyBindings 'test', '*': 'alt-cmd-ctrl-shift-l': 'a'
      keymap.addKeyBindings 'test', '*': 'shift-ctrl-l': 'b'
      keymap.addKeyBindings 'test', '*': 'alt-ctrl-l': 'c'
      keymap.addKeyBindings 'test', '*': 'ctrl-alt--': 'd'

      expect(keymap.findKeyBindings(command: 'a')[0].keystrokes).toBe 'ctrl-alt-shift-cmd-L'
      expect(keymap.findKeyBindings(command: 'b')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymap.findKeyBindings(command: 'c')[0].keystrokes).toBe 'ctrl-alt-l'
      expect(keymap.findKeyBindings(command: 'd')[0].keystrokes).toBe 'ctrl-alt--'

  describe "::removeKeyBindings(source)", ->
    it "removes all bindings originating from the given source", ->
      keymap.addKeyBindings 'foo',
        '.a':
          'ctrl-a': 'x'
        '.b':
          'ctrl-b': 'y'

      keymap.addKeyBindings 'bar',
        '.c':
          'ctrl-c': 'z'

      expect(keymap.findKeyBindings(command: 'x').length).toBe 1
      expect(keymap.findKeyBindings(command: 'y').length).toBe 1
      expect(keymap.findKeyBindings(command: 'z').length).toBe 1

      keymap.removeKeyBindings('bar')

      expect(keymap.findKeyBindings(command: 'x').length).toBe 1
      expect(keymap.findKeyBindings(command: 'y').length).toBe 1
      expect(keymap.findKeyBindings(command: 'z').length).toBe 0

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

  describe "::findKeyBindings({command, target, keystrokes})", ->
    [elementA, elementB] = []
    beforeEach ->
      elementA = appendContent $$ ->
        @div class: 'a', ->
          @div class: 'b c'
          @div class: 'd'
      elementB = elementA.querySelector('.b.c')

      keymap.addKeyBindings 'test',
        '.a':
          'ctrl-a': 'x'
          'ctrl-b': 'y'
        '.b':
          'ctrl-c': 'x'
        '.b.c':
          'ctrl-d': 'x'
        '.d':
          'ctrl-e': 'x'

    describe "when only passed a command", ->
      it "returns all bindings that dispatch the given command", ->
        keystrokes = keymap.findKeyBindings(command: 'x').map((b) -> b.keystrokes).sort()
        expect(keystrokes).toEqual ['ctrl-a', 'ctrl-c', 'ctrl-d', 'ctrl-e']

    describe "when only passed a target", ->
      it "returns all bindings that can be invoked from the given target", ->
        keystrokes = keymap.findKeyBindings(target: elementB).map((b) -> b.keystrokes)
        expect(keystrokes).toEqual ['ctrl-d', 'ctrl-c', 'ctrl-b', 'ctrl-a']

    describe "when passed keystrokes", ->
      it "returns all bindings that can be invoked with the given keystrokes", ->
        keystrokes = keymap.findKeyBindings(keystrokes: 'ctrl-a').map((b) -> b.keystrokes)
        expect(keystrokes).toEqual ['ctrl-a']

    describe "when passed a command and a target", ->
      it "returns all bindings that would invoke the given command from the given target element, ordered by specificity", ->
        keystrokes = keymap.findKeyBindings(command: 'x', target: elementB).map((b) -> b.keystrokes)
        expect(keystrokes).toEqual ['ctrl-d', 'ctrl-c', 'ctrl-a']

  describe "::loadKeyBindings(path, options)", ->
    describe "if called with a file path", ->
      it "loads the keybindings from the file at the given path", ->
        keymap.loadKeyBindings(path.join(__dirname, 'fixtures', 'a.cson'))
        expect(keymap.findKeyBindings(command: 'x').length).toBe 1

      describe "if called with watch: true", ->
        [keymapFilePath, subscription] = []

        beforeEach ->
          keymapFilePath = path.join(temp.mkdirSync('keymap-spec'), "keymap.cson")
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'x'
          """
          subscription = keymap.loadKeyBindings(keymapFilePath, watch: true)
          expect(keymap.findKeyBindings(command: 'x').length).toBe 1

        describe "when the file is changed", ->
          it "reloads the file's key bindings and emits 'reloaded-key-bindings' with the path", ->
            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'y'
              '.b': 'ctrl-b': 'z'
            """

            waitsFor 300, (done) ->
              keymap.once 'reloaded-key-bindings', (filePath) ->
                expect(filePath).toBe keymapFilePath
                done()

            runs ->
              expect(keymap.findKeyBindings(command: 'x').length).toBe 0
              expect(keymap.findKeyBindings(command: 'y').length).toBe 1
              expect(keymap.findKeyBindings(command: 'z').length).toBe 1

          it "logs a warning and does not reload if there is a problem reloading the file", ->
            spyOn(console, 'warn')
            fs.writeFileSync keymapFilePath, "junk1."
            waitsFor 300, -> console.warn.callCount > 0

            runs ->
              expect(keymap.findKeyBindings(command: 'x').length).toBe 1

        describe "when the file is removed", ->
          it "removes the bindings and emits 'unloaded-key-bindings' with the path", ->
            jasmine.unspy(global, 'setTimeout')
            fs.removeSync(keymapFilePath)

            waitsFor 300, (done) ->
              keymap.once 'unloaded-key-bindings', (filePath) ->
                expect(filePath).toBe keymapFilePath
                done()

            runs ->
              expect(keymap.findKeyBindings(command: 'x').length).toBe 0

        describe "when the file is moved", ->
          it "removes the bindings", ->
            jasmine.unspy(global, 'setTimeout')
            newFilePath = path.join(temp.mkdirSync('keymap-spec'), "other-guy.cson")
            fs.moveSync(keymapFilePath, newFilePath)

            waitsFor 300, (done) ->
              keymap.once 'unloaded-key-bindings', (filePath) ->
                expect(filePath).toBe keymapFilePath
                done()

            runs ->
              expect(keymap.findKeyBindings(command: 'x').length).toBe 0

        it "allows the watch to be cancelled via the returned subscription", ->
          subscription.off()
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'y'
            '.b': 'ctrl-b': 'z'
          """

          reloaded = false
          keymap.on 'reloaded-key-bindings', -> reloaded = true

          waits 300
          runs ->
            expect(reloaded).toBe false

          # Can start watching again after cancelling
          runs ->
            keymap.loadKeyBindings(keymapFilePath, watch: true)
            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'q'
            """

          waitsFor 300, (done) ->
            keymap.once 'reloaded-key-bindings', done

          runs ->
            expect(keymap.findKeyBindings(command: 'q').length).toBe 1

    describe "if called with a directory path", ->
      it "loads all platform compatible keybindings files in the directory", ->
        spyOn(keymap, 'getOtherPlatforms').andReturn ['os2']
        keymap.loadKeyBindings(path.join(__dirname, 'fixtures'))
        expect(keymap.findKeyBindings(command: 'x').length).toBe 1
        expect(keymap.findKeyBindings(command: 'y').length).toBe 1
        expect(keymap.findKeyBindings(command: 'z').length).toBe 1
        expect(keymap.findKeyBindings(command: 'X').length).toBe 0
        expect(keymap.findKeyBindings(command: 'Y').length).toBe 0
