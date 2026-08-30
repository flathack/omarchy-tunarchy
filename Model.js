.pragma library

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, Number(value) || 0))
}

function formatTime(seconds) {
  var value = Math.max(0, Math.floor(Number(seconds) || 0))
  var minutes = Math.floor(value / 60)
  var rest = value % 60
  return minutes + ":" + (rest < 10 ? "0" : "") + rest
}

function barLabel(status) {
  if (!status || !status.configured) return "\uf1c0"
  if (!status.track || !status.track.title) return "\uf001"
  return (status.playing ? "\uf04c  " : "\uf04b  ") + status.track.title
}

function safeArray(value) {
  return Array.isArray(value) ? value : []
}

function subtitle(item) {
  if (!item) return ""
  var artist = String(item.artist || "")
  var album = String(item.album || "")
  if (artist && album && artist !== album) return artist + " · " + album
  return artist || album
}
