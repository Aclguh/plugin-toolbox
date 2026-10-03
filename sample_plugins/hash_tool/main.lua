function onInit()
  state.set("input", "")
  state.set("md5Val", "")
  state.set("sha1Val", "")
  state.set("sha256Val", "")
end

function calculate()
  local str = state.get("input") or ""
  if str == "" then
    dialog.toast("请输入内容")
    return
  end

  state.set("md5Val", hash.md5(str))
  state.set("sha1Val", hash.sha1(str))
  state.set("sha256Val", hash.sha256(str))
  dialog.toast("哈希计算完成")
end
