import { createContext, DEFAULT_HOME_URL, getLoginState, getMainPage, waitForLogin } from "./_shared.mjs"

async function main() {
  const cookieString = process.env.XHS_COOKIE ?? ""
  const context = await createContext({ headless: false, cookieString })

  try {
    const page = await getMainPage(context, DEFAULT_HOME_URL)
    const initialState = await getLoginState(page)
    if (initialState.userId && initialState.guest === false) {
      console.log(`已检测到登录态，userId=${initialState.userId}`)
      return
    }

    console.log("已打开小红书页面，请在弹出的浏览器中完成登录。")
    console.log("登录成功后脚本会自动检测并退出。")
    const loggedInState = await waitForLogin(page)

    if (!loggedInState) {
      throw new Error("等待登录超时，请重新运行 `npm run login` 后再试。")
    }

    console.log(`登录成功，userId=${loggedInState.userId}`)
    console.log("登录态已保存在 `tools/xhs/.auth/`。")
  } finally {
    await context.close()
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
