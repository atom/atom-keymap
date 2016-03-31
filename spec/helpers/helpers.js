/* global beforeEach, afterEach */

'use strict'

import lolex from 'lolex'
import sinon from 'sinon'

let sinonSandbox, fakeClock

beforeEach(function () {
  document.body.innerHTML = ''
  sinonSandbox = sinon.sandbox.create()
  fakeClock = lolex.install()
})

afterEach(function () {
  fakeClock.uninstall()
  sinonSandbox.restore()
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
