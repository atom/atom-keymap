# atom-keymap [![Build Status](https://travis-ci.org/atom/atom-keymap.svg?branch=master)](https://travis-ci.org/atom/atom-keymap)

Atom's DOM-aware keymap module

```js
var KeymapManager, keymaps;
KeymapManager = require('atom-keymap')

keymaps = new KeymapManager
keymaps.defaultTarget = document.body

// Pass all the window's keydown events to the KeymapManager
document.addEventListener('keydown', function(event) {
  keymaps.handleKeyboardEvent(event)
})

// Add some keymaps
keymaps.loadKeymap('/path/to/keymap-file.json') // can also be a directory of json / cson files
// OR
keymaps.add('/key/for/these/keymaps', {
  "body": {
    "up": "core:move-up",
    "down": "core:move-down"
  }
})

// When a keybinding is triggered, it will dispatch it on the node that was focused
window.addEventListener('core:move-up', (event) => console.log('up', event))
window.addEventListener('core:move-down', (event) => console.log('down', event))
```

## Development

The tests for this module must be run in Electron.

* For this reason, `devtool` is bundled as a development dependency to run the tests.
* Native modules need to be compiled against the version of Electron included with `devtool`. This should happen automatically on `npm install`, but you can run `electron-rebuild` at any time to recompile native dependencies if you need to.
* Tests should be run with `npm test`
* If you want to use the debugger, profiler, etc or just speed up your flow by being able to refresh the electron window to re-run tests, use the `npm run test-drive` script. This will keep `devtool` open instead of exiting after the test run.
