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
