'use babel'

module.exports =
class PartialKeyupMatcher {

  constructor () {
    this._pendingMatches = new Set()
  }

  addPendingMatch (keyBinding) {
    this._pendingMatches.add(keyBinding)
    keyBinding['nextKeyUpIndex'] = 0
  }

  // Returns matching bindingss, if any.
  // Updates state for next match.
  getMatches (userKeyupKeystroke) {
    userKeyupKeystroke = this._normalizeKeystroke(userKeyupKeystroke)
    let matches = new Set()

    // Loop over each pending keyup match.
    for (const keyBinding of this._pendingMatches) {
      const bindingKeystrokeToMatch = this._normalizeKeystroke(keyBinding.getKeyups()[keyBinding['nextKeyUpIndex']])
      const userKeyups = userKeyupKeystroke.split('-')

      // Attempt to match multi-keyup combinations e.g. ^ctrl-shift
      if (userKeyups.length > 1) {
        if (userKeyupKeystroke === bindingKeystrokeToMatch) {
          this._updateStateForMatch(matches, keyBinding)
        }
      }

      // Loop over individual keys in the user keystroke because we want e.g.
      // user keystroke ^ctrl-shift to match a pending ^ctrl or ^shift.
      for (const userKeyup of userKeyups) {
        if (userKeyup === bindingKeystrokeToMatch) {
          this._updateStateForMatch(matches, keyBinding)
        }
      }
    }
    return [...matches]
  }

  /** Private Section **/

  _normalizeKeystroke (keystroke) {
    if (keystroke[0] === '^') return keystroke.substring(1)
    return keystroke
  }

  _updateStateForMatch (matches, keyBinding) {
    if (keyBinding['nextKeyUpIndex'] === keyBinding.getKeyups().length - 1) {
      // Full match. Remove and return it.
      this._pendingMatches.delete(keyBinding)
      matches.add(keyBinding)
    } else {
      // Partial match. Increment what we're looking for next.
      keyBinding['nextKeyUpIndex']++
    }
  }

}
