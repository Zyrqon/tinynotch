// Плагин opencode для TinyNotch: пишет точный статус каждой сессии в файл
// ~/.local/share/opencode/notch.json, который читает остров.
// Статусы: working (агент работает), waiting (ждёт подтверждения), idle (свободен).
import { writeFileSync, renameSync, existsSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const FILE = join(homedir(), ".local/share/opencode/notch.json")

const sessions = {}
try {
  if (existsSync(FILE)) {
    const prev = JSON.parse(readFileSync(FILE, "utf8"))
    if (prev && prev.sessions) Object.assign(sessions, prev.sessions)
  }
} catch {}

let lastWrite = 0
let writeTimer = null

function set(sessionID, status) {
  if (!sessionID) return
  sessions[sessionID] = { status, ts: Date.now() }
  scheduleWrite()
}

// Пишем не чаще раза в секунду: message.updated приходит часто.
function scheduleWrite() {
  const now = Date.now()
  if (now - lastWrite < 900) {
    if (!writeTimer) writeTimer = setTimeout(() => { writeTimer = null; flush() }, 1000 - (now - lastWrite))
    return
  }
  flush()
}

function flush() {
  try {
    const now = Date.now()
    for (const k of Object.keys(sessions)) if (now - sessions[k].ts > 24 * 3600 * 1000) delete sessions[k]
    const tmp = FILE + ".tmp"
    writeFileSync(tmp, JSON.stringify({ updatedAt: now, sessions }))
    renameSync(tmp, FILE)
    lastWrite = Date.now()
  } catch {}
}

// sessionID может лежать на разной глубине в разных версиях opencode.
function findSessionID(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 4) return null
  if (typeof obj.sessionID === "string") return obj.sessionID
  for (const k of Object.keys(obj)) {
    const hit = findSessionID(obj[k], depth + 1)
    if (hit) return hit
  }
  return null
}

export const NotchStatus = async () => {
  return {
    event: async ({ event }) => {
      try {
        const type = event?.type ?? ""
        const props = event?.properties ?? {}
        if (type === "session.idle" || type === "session.error") {
          set(findSessionID(props), "idle")
        } else if (type.includes("permission")) {
          set(findSessionID(props), "waiting")
        } else if (type === "message.updated") {
          const msg = props?.info
          if (msg?.role === "assistant") set(msg.sessionID, "working")
        } else if (type === "message.part.updated") {
          const st = props?.part?.state?.status
          if (st === "running" || st === "pending") set(findSessionID(props), "working")
        }
      } catch {}
    },
  }
}

export default NotchStatus
