// The radio: lo-fi for pomodoros, a playlist of HoliznaCC0's "Lo-fi And Chill" (CC0, public domain, from the
// Free Music Archive). It plays one after another, can skip, and listens to itself: `levels` for an equalizer, and
// `onBeat` whenever the bass kicks, so things can move to it.

export const TRACKS = [
  { name: "Morning Coffee", tag: "A1", color: "#ec3750", file: "morning-coffee" },
  { name: "Glad To Be Stuck Inside", tag: "B2", color: "#1a73e8", file: "glad-to-be-stuck-inside" },
  { name: "Foggy Headed", tag: "C3", color: "#1e7b45", file: "foggy-headed" },
  { name: "Ramen", tag: "D4", color: "#b06000", file: "ramen" },
  { name: "Creature Comforts", tag: "E5", color: "#8430ce", file: "creature-comforts" }
]
export const ARTIST = "HoliznaCC0"

// A beat is the bass this much louder than it's been lately, at least this long after the last one.
const BEAT_RISE = 1.25
const BEAT_GAP = 280

export class Radio {
  // `urls` maps each track's file to where it's served.
  constructor(urls, onBeat) {
    this.urls = urls
    this.onBeat = onBeat
    this.track = 0
    this.element = new Audio()
    this.element.preload = "auto"
    this.element.addEventListener("ended", () => this.next())

    const audio = this.audio = new (window.AudioContext || window.webkitAudioContext)()
    this.analyser = audio.createAnalyser()
    this.analyser.fftSize = 128
    this.analyser.smoothingTimeConstant = 0.78
    audio.createMediaElementSource(this.element).connect(this.analyser)
    this.analyser.connect(audio.destination)
    this.bass = 0
    this.lastBeat = 0
    this.#load()
  }

  get playing() {
    return !this.element.paused
  }

  play() {
    this.audio.resume()
    return this.element.play().catch(() => {})
  }

  pause() {
    this.element.pause()
  }

  setTrack(index) {
    const playing = this.playing
    this.track = index
    this.#load()
    if (playing) this.play()
  }

  next() {
    this.setTrack((this.track + 1) % TRACKS.length)
    this.play()
    this.onTrack?.(this.track)
  }

  // Three rising notes, for a round done.
  chime() {
    const now = this.audio.currentTime;
    [ 76, 79, 84 ].forEach((note, index) => {
      const time = now + index * 0.14
      const oscillator = this.audio.createOscillator()
      const gain = this.audio.createGain()
      oscillator.frequency.value = 440 * Math.pow(2, (note - 69) / 12)
      gain.gain.setValueAtTime(0.0001, time)
      gain.gain.exponentialRampToValueAtTime(0.16, time + 0.01)
      gain.gain.exponentialRampToValueAtTime(0.0001, time + 1.4)
      oscillator.connect(gain)
      gain.connect(this.audio.destination)
      oscillator.start(time)
      oscillator.stop(time + 1.5)
    })
  }

  // How loud each band is right now, 0 to 1, for an equalizer; also how beats get noticed.
  levels(count) {
    const data = new Uint8Array(this.analyser.frequencyBinCount)
    if (this.playing) this.analyser.getByteFrequencyData(data)
    this.#listenForBeat(data)
    return Array.from({ length: count }, (_, index) => data[1 + index * 2] / 255)
  }

  close() {
    this.onBeat = null
    this.element.pause()
    this.element.removeAttribute("src")
    this.audio.close()
  }

  #load() {
    this.element.src = this.urls[TRACKS[this.track].file]
  }

  #listenForBeat(data) {
    const now = performance.now()
    const level = (data[1] + data[2] + data[3]) / 3
    if (this.playing && level > this.bass * BEAT_RISE && level > 60 && now - this.lastBeat > BEAT_GAP) {
      this.lastBeat = now
      this.onBeat?.()
    }
    this.bass = this.bass * 0.9 + level * 0.1
  }
}
