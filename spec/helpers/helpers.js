/* global beforeEach, afterEach */

'use strict'

import lolex from 'lolex'
import sinon from 'sinon'

let sinonSandbox, fakeClock, processPlatform, originalProcessPlatform

originalProcessPlatform = process.platform
processPlatform = process.platform
Object.defineProperty(process, 'platform', {get: () => processPlatform})

beforeEach(function () {
  document.body.innerHTML = ''
  sinonSandbox = sinon.sandbox.create()
  fakeClock = lolex.install()
})

afterEach(function () {
  fakeClock.uninstall()
  sinonSandbox.restore()
  processPlatform = originalProcessPlatform
})

export function appendContent (element) {
  document.body.appendChild(element)
  return element
}

export function stub () {
  return sinonSandbox.stub(...arguments)
}

export function getFakeClock () {
  return fakeClock
}

export function mockProcessPlatform (platform) {
  processPlatform = platform
}

export function buildKeydownEvent (props) {
  return buildKeyboardEvent('keydown', props)
}

export function buildKeyupEvent (props) {
  return buildKeyboardEvent('keyup', props)
}

export function buildKeyboardEvent (type, props) {
  let {key, code, ctrlKey, shiftKey, altKey, metaKey, target, modifierState} = props
  if (!modifierState) modifierState = {}

  if (process.platform === 'darwin') {
    if (modifierState.AltGraph) {
      altKey = true
    }
  } else if (process.platform === 'win32') {
    if (modifierState.AltGraph) {
      ctrlKey = true
      altKey = true
    } else if (ctrlKey && altKey) {
      modifierState.AltGraph = true
    }
  }

  const event = new KeyboardEvent(type, {
    key, code,
    ctrlKey, shiftKey, altKey, metaKey,
    cancelable: true, bubbles: true
  })

  if (target) {
    Object.defineProperty(event, 'target', {get: () => target})
    Object.defineProperty(event, 'path', {get: () => [target]})
  }

  Object.defineProperty(event, 'getModifierState', {value: (key) => {
    return !!modifierState[key]
  }})

  return event
}
