processes := ["StreamDeck.exe", "lghub.exe"]  ; 需要关闭的进程列表
winClosed := Map()  ; 记录每个进程是否关闭过

for process in processes
    winClosed[process] := false  ; 初始化关闭状态

;---------------------------
; 带重试机制的关闭函数
TryCloseWindowWithRetry(process, maxRetries := 5, retryInterval := 500) {
    retries := 0
    Loop {
        try {
            if WinExist("ahk_exe " process) {
                Sleep retryInterval ; 稍微等一下 确保窗口完全加载
                WinClose("ahk_exe " process) ; 尝试 WinClose
                return true
            }
        } catch {
            ; 捕获到错误，啥也不做，继续重试
        }
        retries++
        if retries >= maxRetries
            break
    }
    return false  ; 超过最大重试次数还没关掉
}

Loop {
    allClosed := true  ; 假设所有进程的窗口都已经关闭

    for process in processes {
        ; 尝试带重试关闭窗口
        if TryCloseWindowWithRetry(process, 5, 500) {  ; 最多重试5次，每次间隔500ms
            winClosed[process] := true ; 记录该窗口已关闭
        }

        if !winClosed[process] ; 如果有窗口未关闭过，继续循环
            allClosed := false
    }

    if allClosed ; 所有进程的窗口都已关闭一次，退出循环
        break

    Sleep 500 ; 每 500ms 重新检查一次
}

ExitApp