# atom-keymap [![Build Status](https://travis-ci.org/atom/atom-keymap.svg?branch=master)](https://travis-ci.org/atom/atom-keymap)

Atom's DOM-aware keymap module

```js
var KeymapManager = require('atom-keymap')

this.keymaps = new KeymapManager
this.keymaps.defaultTarget = document.body

// Pass all the window's keydown events to the KeymapManager
document.addEventListener('keydown', function(event) {
  keymaps.handleKeyboardEvent(event)
})

// Add some keymaps
this.keymaps.loadKeymap('/path/to/keymap-file.json') // can also be a directory of json / cson files
// OR
this.keymaps.add('/key/for/these/keymaps', {
  "body": {
    "up": "core:move-up",
    "down": "core:move-down"
  }
})

// When a keybinding is triggered, it will dispatch it on the node was focused
window.addEventListener('core:move-up', (event) => console.log('up', event))
window.addEventListener('core:move-down', (event) => console.log('down', event))
```
