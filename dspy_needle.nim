import std/[httpclient, json, macros, strutils]
import nimpy

const NeedleEndpoint* = "http://127.0.0.1:7860/generate"

type NeedleDspyModule* = ref object of RootObj
  endpoint*: string
  tools*: JsonNode
  request*: string
  candidate*: JsonNode

type DspyField* = object
  description*: string
  nature*: string

proc input*(description, nature: string): DspyField =
  DspyField(description: description, nature: nature)

proc output*(description, nature: string): DspyField =
  DspyField(description: description, nature: nature)

proc buildSignature(nature: string, body: NimNode): string =
  var inputs, outputs: seq[string]
  for statement in body:
    if statement.kind != nnkAsgn: continue
    let fieldName = statement[0].strVal
    let call = statement[1]
    if call.kind != nnkCall or call.len < 1: continue
    var description, fieldNature = ""
    for argument in call[1 .. ^1]:
      if argument.kind == nnkExprEqExpr:
        if argument[0].strVal == "desc": description = argument[1].strVal
        if argument[0].strVal == "nature": fieldNature = argument[1].strVal
    let rendered = fieldName & " {nature=" & fieldNature & "; desc=" & description & "}"
    if call[0].strVal == "input": inputs.add(rendered)
    elif call[0].strVal == "output": outputs.add(rendered)
  inputs.join(", ") & " -> " & outputs.join(", ") & " [mode=" & nature & "]"

macro dspySignature*(name, nature: untyped, body: untyped): untyped =
  let signature = newLit(buildSignature(nature.strVal, body))
  let exportedName = name
  quote do:
    const `exportedName`* = `signature`

template dspyChainOfThought*(dspy: PyObject, signature: static[string]): PyObject {.dirty.} =
  dspy.ChainOfThought(signature)

proc dspyRuntime*(model, signature: string): PyObject =
  let dspy = pyImport("dspy")
  discard dspy.configure(lm = dspy.LM(model))
  let marker = " [mode="
  let markerAt = signature.rfind(marker)
  let baseSignature = if markerAt >= 0: signature[0 ..< markerAt] else: signature
  let mode = if markerAt >= 0:
    signature[markerAt + marker.len .. ^2]
  else: "chain"
  case mode.toLowerAscii()
  of "react": dspy.ReAct(baseSignature)
  of "forward": dspy.Predict(baseSignature)
  else: dspy.ChainOfThought(baseSignature)

macro dspyModule*(name: untyped, body: untyped): untyped =
  ## Declara um módulo com construtor e forward, no estilo dspy.Module.
  var signature = newLit("")
  var signatureName = ident("signature")
  for statement in body:
    if statement.kind in {nnkCall, nnkCommand} and statement[0].strVal == "dspySignature":
      signatureName = ident(statement[1].strVal)
      signature = newLit(buildSignature(statement[2].strVal, statement[3]))
      break
  let procResult = ident("result")
  var forwardBody = body
  if body.kind == nnkStmtList:
    for statement in body:
      if statement.kind == nnkCall and statement[0].strVal == "forward":
        forwardBody = statement[1]
        break
  result = quote do:
    type `name`* = ref object of NeedleDspyModule
      `signatureName`*: PyObject

    proc new*(T: typedesc[`name`], model: string, tools: JsonNode,
        endpoint: string = NeedleEndpoint): `name` =
      `procResult` = `name`(
        endpoint: endpoint,
        tools: tools,
        `signatureName`: dspyRuntime(model, `signature`)
      )

    proc forward*(self: `name`, request: string,
        candidate: JsonNode): JsonNode =
      let this {.inject.} = self
      this.request = request
      this.candidate = candidate
      `forwardBody`


proc needleGenerate*(module: NeedleDspyModule, query: string): JsonNode =
  let payload = %*{
    "query": query, "tools": module.tools, "seed": 0,
    "max_gen_len": 128, "constrained": true
  }
  var client = newHttpClient()
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let response = client.request(module.endpoint, httpMethod = HttpPost, body = $payload)
  if not response.code.is2xx:
    raise newException(IOError, "Needle returned " & $response.code & ": " & response.body)
  let envelope = parseJson(response.body)
  if envelope.hasKey("error"):
    raise newException(IOError, envelope["error"].getStr())
  let calls = parseJson(envelope["result"].getStr())
  if calls.kind != JArray or calls.len == 0:
    raise newException(ValueError, "Needle returned no tool call: " & $calls)
  calls[0]
