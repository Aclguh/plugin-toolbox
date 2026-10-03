function onInit()
  state.set("inputText", "")
  state.set("resultText", "")
  state.set("hasError", false)
  state.set("errorMsg", "")
end

function encode()
  local input = state.get("inputText")
  if not input or input == "" then
    state.set("hasError", true)
    state.set("errorMsg", "请输入要编码的文本内容")
    return
  end

  local encoded = codec.base64Encode(input)
  state.set("resultText", encoded)
  state.set("hasError", false)
  dialog.toast("Base64 编码完成")
end

function decode()
  local input = state.get("inputText")
  if not input or input == "" then
    state.set("hasError", true)
    state.set("errorMsg", "请输入要解码的 Base64 字符串")
    return
  end

  local ok, res = pcall(codec.base64Decode, input)
  if ok then
    state.set("resultText", res)
    state.set("hasError", false)
    dialog.toast("Base64 解码完成")
  else
    state.set("hasError", true)
    state.set("errorMsg", "解码失败：输入的不是合法的 Base64 格式")
  end
end

function swapText()
  local inVal = state.get("inputText") or ""
  local outVal = state.get("resultText") or ""
  state.set("inputText", outVal)
  state.set("resultText", inVal)
end
