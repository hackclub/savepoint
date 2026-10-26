// Three rising notes for "goal set", made here because there is no file for it. Quiet, and a browser that refuses is
// silence. Used by the shop's sheet (prize_sheet_controller.js) and the project page's prize row (prize_picker_controller.js).
let context

export function chime() {
  try {
    context ||= new (window.AudioContext || window.webkitAudioContext)()
    context.resume?.()
    ;[ 659.25, 783.99, 1046.5 ].forEach((frequency, i) => {
      const osc = context.createOscillator(), gain = context.createGain(), at = context.currentTime + 0.05 + i * 0.07
      osc.type = "triangle"
      osc.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, at)
      gain.gain.exponentialRampToValueAtTime(0.12, at + 0.012)
      gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.26)
      osc.connect(gain).connect(context.destination)
      osc.start(at)
      osc.stop(at + 0.3)
    })
  } catch {}
}
