-- [[ settings page ]]
--!optimize 2
-- @modules pagesettings
local UIPage = {}
UIPage.definition = {
  id = "config",
  title = "Configurações",
  columns = 1,
  utility = true,
  sections = {
    {
      title = "Inicialização e atualizações",
      components = {
        { kind = "toggle", title = "Auto Execute", key = "AutoExecuteOnJoin", description = "Executa ao entrar. Depende do executor." },
        {
          kind = "toggle",
          title = "Todos os jogos",
          key = "AutoExecuteAllGames",
          parentKey = "AutoExecuteOnJoin",
          description = "Desativado: apenas este jogo.",
        },
        { kind = "toggle", title = "Atualizar automaticamente", key = "AutoExecute" },
      },
    },
    {
      title = "Interface",
      components = {
        { kind = "toggle", title = "Modo PC", key = "ForcePCUI", description = "Usa os controles de desktop.", desktopExpanded = true },
        {
          kind = "slider",
          title = "Tamanho geral das Mini UIs",
          key = "MiniUIScale",
          min = 0.5,
          max = 2,
          increment = 0.05,
          valueName = "x",
          description = "Aumenta ou diminui todas, mantendo o tamanho individual de cada uma. 1x mantém os tamanhos configurados.",
          mobileOnly = true,
        },
      },
    },
    {
      title = "Notificações",
      components = {
        { kind = "toggle", title = "Notificações em balão", key = "DesktopNotifications", desktopOnly = true },
        { kind = "toggle", title = "Avisos de atalhos", key = "DesktopShortcutNotifications", parentKey = "DesktopNotifications", desktopOnly = true },
        { kind = "toggle", title = "Notificações em balão", key = "MobileNotifications", mobileOnly = true },
        { kind = "toggle", title = "Avisos no canto inferior direito", key = "CornerNotifications" },
      },
    },
    {
      title = "Personagem e servidor",
      components = {
        { kind = "button", title = "Resetar personagem", action = "resetCharacter" },
        { kind = "button", title = "Rejoin", action = "rejoin" },
        { kind = "button", title = "Server Hop", action = "serverHop", description = "Busca outro servidor com ping até 100 ms." },
      },
    },
    { title = "Preferências", components = { { kind = "button", title = "Reset settings", action = "resetSettings" } } },
  },
}
function UIPage.setup() return true end
UIPage.__contract = { page = 20, provides = { "setup" }, data = { "definition" }, requires = {} }
return UIPage
