import std/[httpclient, json, os, strutils, uri]
import dspy_needle
import nimpy

dspyModule ToolReasoner:
  """Valida chamadas de ferramentas geradas pelo Needle usando Chain-of-Thought."""
  dspySignature ToolReasoningSignature, chain:
    request = input(desc = "User's natural-language request", nature = "input/proprietary")
    candidate = input(desc = "Tool call proposed by Needle", nature = "input/derived")
    approved = output(desc = "Whether the proposed call is safe", nature = "output/decision")
    toolName = output(desc = "Validated tool identifier", nature = "output/proprietary")
    argumentsJson = output(desc = "Validated tool arguments", nature = "output/structured")
  forward:
    let prediction = this.ToolReasoningSignature.forward(
      request = this.request,
      candidate = $this.candidate)
    let approved = ($getAttr(prediction, "approved")).strip().toLowerAscii() in ["true", "1", "yes"]
    return %*{"approved": approved, "tool_name": $getAttr(prediction, "tool_name"),
               "arguments_json": $getAttr(prediction, "arguments_json")}

proc webSearch(query: string) =
  var client = newHttpClient(userAgent = "needle-nim-example/1.0")
  defer: client.close()
  let html = client.getContent("https://lite.duckduckgo.com/lite/?q=" & encodeUrl(query))
  let lines = html.splitLines()
  var shown = 0
  for line in lines:
    if "result-link" in line or "result-snippet" in line:
      echo line.strip()
      inc shown
      if shown >= 5: break
  if shown == 0: echo "[web] no results for: ", query

proc fetchUrl(url: string) =
  if not (url.startsWith("https://") or url.startsWith("http://")):
    raise newException(ValueError, "only http(s) URLs are allowed")
  var client = newHttpClient(userAgent = "needle-nim-example/1.0")
  defer: client.close()
  let content = client.getContent(url)
  echo content[0 ..< min(content.len, 2000)]

proc saveNote(title, content: string) =
  let dir = getEnv("NEEDLE_NOTES_DIR", getCurrentDir() / "notes")
  createDir(dir)
  let safeTitle = title.toLowerAscii().replace(" ", "_")
  let path = dir / (safeTitle & ".md")
  writeFile(path, "# " & title & "\n\n" & content & "\n")
  echo "[local] saved note: ", path

proc controlLights(room, action: string) =
  if action notin ["on", "off", "dim"]:
    raise newException(ValueError, "invalid light action: " & action)
  let path = getEnv("NEEDLE_LIGHTS_STATE", getCurrentDir() / "lights.json")
  var state = if fileExists(path): parseJson(readFile(path)) else: newJObject()
  state[room] = %*action
  writeFile(path, $state)
  echo "[local] lights ", room, " -> ", action

proc main() =
  let model = getEnv("DSPY_MODEL")
  if model.len == 0: raise newException(ValueError, "set DSPY_MODEL before running")
  let query = if paramCount() > 0: commandLineParams().join(" ") else: "Apague as luzes da cozinha"
  let module = ToolReasoner.new(model, %*[
    {"name": "web_search", "description": "Search public web results.",
     "parameters": {"query": {"type": "string", "required": true}}},
    {"name": "fetch_url", "description": "Fetch readable text from a URL.",
     "parameters": {"url": {"type": "string", "required": true}}},
    {"name": "control_lights", "description": "Control lights in a local room.",
     "parameters": {"room": {"type": "string", "required": true},
                    "action": {"type": "string", "required": true}}},
    {"name": "save_note", "description": "Save a note on the local device.",
     "parameters": {"title": {"type": "string", "required": true},
                    "content": {"type": "string", "required": true}}}
  ])
  let candidate = module.needleGenerate(query)
  let decision = module.forward(query, candidate)
  if not decision["approved"].getBool(): raise newException(ValueError, "DSPy rejected the call")
  let args = parseJson(decision["arguments_json"].getStr())
  if decision["tool_name"].getStr() != candidate["name"].getStr():
    raise newException(ValueError, "DSPy changed the tool name")
  case candidate["name"].getStr()
  of "web_search": webSearch(args["query"].getStr())
  of "fetch_url": fetchUrl(args["url"].getStr())
  of "control_lights": controlLights(args["room"].getStr(), args["action"].getStr())
  of "save_note": saveNote(args["title"].getStr(), args["content"].getStr())
  else: raise newException(ValueError, "unknown tool: " & candidate["name"].getStr())

when isMainModule: main()
